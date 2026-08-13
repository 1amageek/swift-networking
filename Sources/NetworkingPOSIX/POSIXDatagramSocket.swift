#if canImport(Darwin) || canImport(Glibc) || canImport(Musl)

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

import _Concurrency
import NetworkingCore
import NetworkingDatagram
import Synchronization

typealias ReceiveResult = Result<InboundDatagram?, DatagramError>
typealias ShutdownResult = Result<Void, DatagramError>
typealias ReceiveContinuation = CheckedContinuation<ReceiveResult, Never>
typealias ShutdownContinuation = CheckedContinuation<ShutdownResult, Never>

/// Owns one UDP descriptor, its wakeup pipe, and the dedicated receive worker.
///
/// Unsafe boundary invariants:
/// - this object is the sole owner of all three descriptors;
/// - the receive worker retains this owner until it exits;
/// - descriptor close occurs exactly once, after the worker and all synchronous
///   descriptor operations have finished;
/// - borrowed payload pointers remain scoped to one synchronous syscall;
/// - all shared lifecycle, waiter, queue, and statistics state is protected by
///   the same `Mutex<SocketState>` on every supported target.
final class POSIXDatagramSocket: Sendable {
    private let state: Mutex<SocketState>
    private let receiveBufferSize: Int
    private let receiveRegistrationObserver: (@Sendable () -> Void)?

    init(
        bindingTo endpoint: IPSocketEndpoint,
        receiveBufferSize: Int,
        receiveBuffering: DatagramReceiveBuffering,
        reuseForMulticast: Bool,
        receiveRegistrationObserver: (@Sendable () -> Void)? = nil
    ) throws(DatagramError) {
        guard receiveBufferSize > 0 else {
            throw .invalidBufferCapacity(receiveBufferSize)
        }

        let family = POSIXSocketAddressCodec.family(of: endpoint)
        let descriptor = socket(family, posixDatagramSocketType, 0)
        guard descriptor >= 0 else {
            throw .backendFailure(operation: .bind, code: Int(posixErrno), terminal: true)
        }

        do {
            try Self.configureReuse(
                descriptor: descriptor,
                required: reuseForMulticast
            )
        } catch {
            _ = posixClose(descriptor)
            throw error
        }

        var pipeDescriptors: (Int32, Int32) = (-1, -1)
        let pipeResult = withUnsafeMutablePointer(to: &pipeDescriptors) { pointer in
            pointer.withMemoryRebound(to: Int32.self, capacity: 2) {
                pipe($0)
            }
        }
        guard pipeResult == 0 else {
            let code = posixErrno
            _ = posixClose(descriptor)
            throw .backendFailure(operation: .bind, code: Int(code), terminal: true)
        }

        var encoded = POSIXSocketAddressCodec.encode(endpoint)
        let bindResult = withUnsafePointer(to: &encoded.storage) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                posixBind(descriptor, $0, encoded.length)
            }
        }
        guard bindResult == 0 else {
            let code = posixErrno
            _ = posixClose(descriptor)
            _ = posixClose(pipeDescriptors.0)
            _ = posixClose(pipeDescriptors.1)
            throw .backendFailure(operation: .bind, code: Int(code), terminal: true)
        }

        state = Mutex(
            SocketState(
                socketDescriptor: descriptor,
                wakeReadDescriptor: pipeDescriptors.0,
                wakeWriteDescriptor: pipeDescriptors.1,
                queue: DatagramQueue(capacity: receiveBuffering.capacity),
                overflowPolicy: receiveBuffering.overflowPolicy
            )
        )
        self.receiveBufferSize = receiveBufferSize
        self.receiveRegistrationObserver = receiveRegistrationObserver

        let workerResult = startReceiveWorker()
        guard workerResult == 0 else {
            let descriptors = state.withLock { state -> DescriptorSet in
                state.lifecycle = .terminal(
                    .backendFailure(
                        operation: .receive,
                        code: Int(workerResult),
                        terminal: true
                    )
                )
                state.workerExited = true
                state.finalized = true
                return state.takeDescriptors()
            }
            descriptors.close()
            throw .backendFailure(
                operation: .receive,
                code: Int(workerResult),
                terminal: true
            )
        }
    }

    func boundEndpoint() throws(DatagramError) -> IPSocketEndpoint {
        let descriptor = try beginDescriptorOperation()
        defer { endDescriptorOperation() }

        var storage = sockaddr_storage()
        var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let result = withUnsafeMutablePointer(to: &storage) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        }
        guard result == 0 else {
            throw .backendFailure(
                operation: .bind,
                code: Int(posixErrno),
                terminal: false
            )
        }
        guard let endpoint = POSIXSocketAddressCodec.decode(storage) else {
            throw .invalidEndpoint
        }
        return endpoint
    }

    func send(
        _ payload: borrowing OwnedBytes,
        to endpoint: IPSocketEndpoint
    ) throws(DatagramError) {
        let descriptor = try beginDescriptorOperation()
        defer { endDescriptorOperation() }

        var encoded = POSIXSocketAddressCodec.encode(endpoint)
        let sent = payload.withBorrowedBytes { bytes in
            bytes.bytes.withUnsafeBytes { rawBuffer in
                withUnsafePointer(to: &encoded.storage) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        posixSendTo(
                            descriptor,
                            buffer: rawBuffer.baseAddress,
                            length: rawBuffer.count,
                            address: $0,
                            addressLength: encoded.length
                        )
                    }
                }
            }
        }

        guard sent >= 0 else {
            throw .backendFailure(
                operation: .send,
                code: Int(posixErrno),
                terminal: false
            )
        }
        guard sent == payload.count else {
            throw .backendFailure(
                operation: .send,
                code: Int(EMSGSIZE),
                terminal: false
            )
        }
    }

    func reserveReceiveToken() -> UInt64 {
        state.withLock { state in
            let token = state.nextReceiveToken
            state.nextReceiveToken &+= 1
            state.reservedReceiveTokens.insert(token)
            return token
        }
    }

    func registerReceive(
        token: UInt64,
        continuation: ReceiveContinuation
    ) {
        let registration: (immediate: ReceiveResult?, didRegister: Bool) = state.withLock { state in
            guard state.reservedReceiveTokens.remove(token) != nil else {
                return (.failure(.cancelled), false)
            }
            if state.cancelledReceiveTokens.remove(token) != nil {
                return (.failure(.cancelled), false)
            }

            switch state.lifecycle {
            case .open:
                if state.receiveWaiter != nil {
                    return (.failure(.concurrentReceive), false)
                }
                if let datagram = state.queue.dequeue() {
                    return (.success(datagram), false)
                }
                state.receiveWaiter = ReceiveWaiter(
                    token: token,
                    continuation: continuation
                )
                return (nil, true)

            case let .shutdownRequested(error), let .terminal(error):
                if let error {
                    return (.failure(error), false)
                }
                return (.success(nil), false)
            }
        }

        if registration.didRegister {
            receiveRegistrationObserver?()
        }
        if let immediate = registration.immediate {
            continuation.resume(returning: immediate)
        }
    }

    func cancelReceive(token: UInt64) {
        let continuation: ReceiveContinuation? = state.withLock { state in
            if state.reservedReceiveTokens.contains(token) {
                state.cancelledReceiveTokens.insert(token)
                return nil
            }
            guard state.receiveWaiter?.token == token else {
                return nil
            }
            let continuation = state.receiveWaiter?.continuation
            state.receiveWaiter = nil
            return continuation
        }
        continuation?.resume(returning: .failure(.cancelled))
    }

    func statistics() -> DatagramReceiveStatistics {
        state.withLock {
            DatagramReceiveStatistics(
                receivedDatagramCount: $0.receivedDatagramCount,
                droppedDatagramCount: $0.droppedDatagramCount
            )
        }
    }

    func registerShutdown(_ continuation: ShutdownContinuation) {
        let actions: ShutdownRegistrationActions = state.withLock { state in
            switch state.lifecycle {
            case .open:
                state.lifecycle = .shutdownRequested(nil)
                let receiveContinuation = state.receiveWaiter?.continuation
                state.receiveWaiter = nil
                state.queue.removeAll()
                state.shutdownWaiters.append(continuation)
                return ShutdownRegistrationActions(
                    receiveContinuation: receiveContinuation,
                    immediateResult: nil,
                    shouldWakeWorker: true,
                    wakeDescriptor: state.wakeWriteDescriptor,
                    socketDescriptor: state.socketDescriptor
                )

            case .shutdownRequested:
                state.shutdownWaiters.append(continuation)
                return ShutdownRegistrationActions()

            case let .terminal(error):
                if state.finalized {
                    return ShutdownRegistrationActions(
                        immediateResult: Self.shutdownResult(error)
                    )
                }
                state.shutdownWaiters.append(continuation)
                return ShutdownRegistrationActions()
            }
        }

        actions.receiveContinuation?.resume(returning: .success(nil))
        if let immediateResult = actions.immediateResult {
            continuation.resume(returning: immediateResult)
        }
        if actions.shouldWakeWorker {
            wakeWorker(
                wakeDescriptor: actions.wakeDescriptor,
                socketDescriptor: actions.socketDescriptor
            )
        }
    }

    func requestShutdownWithoutWaiting() {
        let actions: ShutdownRegistrationActions = state.withLock { state in
            guard case .open = state.lifecycle else {
                return ShutdownRegistrationActions()
            }
            state.lifecycle = .shutdownRequested(nil)
            let receiveContinuation = state.receiveWaiter?.continuation
            state.receiveWaiter = nil
            state.queue.removeAll()
            return ShutdownRegistrationActions(
                receiveContinuation: receiveContinuation,
                shouldWakeWorker: true,
                wakeDescriptor: state.wakeWriteDescriptor,
                socketDescriptor: state.socketDescriptor
            )
        }
        actions.receiveContinuation?.resume(returning: .success(nil))
        if actions.shouldWakeWorker {
            wakeWorker(
                wakeDescriptor: actions.wakeDescriptor,
                socketDescriptor: actions.socketDescriptor
            )
        }
    }

    func setMembership(
        group: IPAddress,
        interface: NetworkInterfaceIndex?,
        join: Bool
    ) throws(DatagramError) {
        guard group.isMulticast else {
            throw .invalidEndpoint
        }
        let descriptor = try beginDescriptorOperation()
        defer { endDescriptorOperation() }

        let result: Int32
        switch group {
        case let .v4(a, b, c, d):
            var request = ip_mreq()
            let packed = (UInt32(a) << 24)
                | (UInt32(b) << 16)
                | (UInt32(c) << 8)
                | UInt32(d)
            request.imr_multiaddr.s_addr = packed.bigEndian
            if let interface {
                guard let interfaceAddress = Self.ipv4Address(for: interface) else {
                    throw .invalidEndpoint
                }
                request.imr_interface = interfaceAddress
            } else {
                request.imr_interface.s_addr = INADDR_ANY
            }
            let option = join ? IP_ADD_MEMBERSHIP : IP_DROP_MEMBERSHIP
            result = withUnsafePointer(to: &request) {
                posixSetSocketOption(
                    descriptor,
                    level: Int32(IPPROTO_IP),
                    option: Int32(option),
                    value: $0,
                    length: socklen_t(MemoryLayout<ip_mreq>.size)
                )
            }

        case let .v6(octets):
            var request = ipv6_mreq()
            withUnsafeMutableBytes(of: &request.ipv6mr_multiaddr) { destination in
                let source = octets.toContiguousArray()
                source.withUnsafeBytes { destination.copyMemory(from: $0) }
            }
            request.ipv6mr_interface = interface?.rawValue ?? 0
            let option = join ? IPV6_JOIN_GROUP : IPV6_LEAVE_GROUP
            result = withUnsafePointer(to: &request) {
                posixSetSocketOption(
                    descriptor,
                    level: Int32(IPPROTO_IPV6),
                    option: Int32(option),
                    value: $0,
                    length: socklen_t(MemoryLayout<ipv6_mreq>.size)
                )
            }
        }

        guard result == 0 else {
            throw .backendFailure(
                operation: .multicast,
                code: Int(posixErrno),
                terminal: false
            )
        }
    }

    func configureMulticast(
        _ configuration: MulticastConfiguration,
        for family: IPAddressFamily
    ) throws(DatagramError) {
        let descriptor = try beginDescriptorOperation()
        defer { endDescriptorOperation() }

        if let interface = configuration.interfaceIndex {
            try Self.setMulticastInterface(
                descriptor: descriptor,
                interface: interface,
                family: family
            )
        }

        var hopLimit = Int32(configuration.hopLimit)
        let hopResult: Int32
        switch family {
        case .ipv4:
            hopResult = posixSetSocketOption(
                descriptor,
                level: Int32(IPPROTO_IP),
                option: Int32(IP_MULTICAST_TTL),
                value: &hopLimit,
                length: socklen_t(MemoryLayout<Int32>.size)
            )
        case .ipv6:
            hopResult = posixSetSocketOption(
                descriptor,
                level: Int32(IPPROTO_IPV6),
                option: Int32(IPV6_MULTICAST_HOPS),
                value: &hopLimit,
                length: socklen_t(MemoryLayout<Int32>.size)
            )
        }
        guard hopResult == 0 else {
            throw .backendFailure(
                operation: .multicast,
                code: Int(posixErrno),
                terminal: false
            )
        }

        var loopback = Int32(configuration.loopbackEnabled ? 1 : 0)
        let loopResult: Int32
        switch family {
        case .ipv4:
            loopResult = posixSetSocketOption(
                descriptor,
                level: Int32(IPPROTO_IP),
                option: Int32(IP_MULTICAST_LOOP),
                value: &loopback,
                length: socklen_t(MemoryLayout<Int32>.size)
            )
        case .ipv6:
            loopResult = posixSetSocketOption(
                descriptor,
                level: Int32(IPPROTO_IPV6),
                option: Int32(IPV6_MULTICAST_LOOP),
                value: &loopback,
                length: socklen_t(MemoryLayout<Int32>.size)
            )
        }
        guard loopResult == 0 else {
            throw .backendFailure(
                operation: .multicast,
                code: Int(posixErrno),
                terminal: false
            )
        }
    }

    deinit {
        let descriptors: DescriptorSet = state.withLock { state in
            guard !state.finalized else {
                return DescriptorSet()
            }
            state.finalized = true
            return state.takeDescriptors()
        }
        descriptors.close()
    }

    private static func configureReuse(
        descriptor: Int32,
        required: Bool
    ) throws(DatagramError) {
        var enabled: Int32 = 1
        let addressResult = posixSetSocketOption(
            descriptor,
            level: Int32(SOL_SOCKET),
            option: Int32(SO_REUSEADDR),
            value: &enabled,
            length: socklen_t(MemoryLayout<Int32>.size)
        )
        if required, addressResult != 0 {
            throw .backendFailure(
                operation: .bind,
                code: Int(posixErrno),
                terminal: true
            )
        }
        guard required else { return }

        let portResult = posixSetSocketOption(
            descriptor,
            level: Int32(SOL_SOCKET),
            option: Int32(SO_REUSEPORT),
            value: &enabled,
            length: socklen_t(MemoryLayout<Int32>.size)
        )
        guard portResult == 0 else {
            throw .backendFailure(
                operation: .bind,
                code: Int(posixErrno),
                terminal: true
            )
        }
    }

    private func beginDescriptorOperation() throws(DatagramError) -> Int32 {
        try state.withLock { state throws(DatagramError) -> Int32 in
            switch state.lifecycle {
            case .open:
                guard state.socketDescriptor >= 0 else {
                    throw .closed
                }
                state.activeDescriptorOperationCount += 1
                return state.socketDescriptor
            case let .shutdownRequested(error), let .terminal(error):
                if let error {
                    throw error
                }
                throw .closed
            }
        }
    }

    private func endDescriptorOperation() {
        let finalization: FinalizationActions? = state.withLock { state in
            precondition(state.activeDescriptorOperationCount > 0)
            state.activeDescriptorOperationCount -= 1
            return Self.makeFinalizationActionsIfReady(state: &state)
        }
        finalization?.perform()
    }

    private func startReceiveWorker() -> Int32 {
        let unmanaged = Unmanaged.passRetained(self)

        #if canImport(Darwin)
        var thread: pthread_t? = nil
        let result = pthread_create(
            &thread,
            nil,
            { rawContext in
                let socket = Unmanaged<POSIXDatagramSocket>
                    .fromOpaque(rawContext)
                    .takeRetainedValue()
                socket.runReceiveLoop()
                return nil
            },
            unmanaged.toOpaque()
        )
        if result == 0, let thread {
            pthread_detach(thread)
        } else {
            unmanaged.release()
        }
        return result
        #else
        var thread = pthread_t()
        let result = pthread_create(
            &thread,
            nil,
            { rawContext in
                guard let rawContext else { return nil }
                let socket = Unmanaged<POSIXDatagramSocket>
                    .fromOpaque(rawContext)
                    .takeRetainedValue()
                socket.runReceiveLoop()
                return nil
            },
            unmanaged.toOpaque()
        )
        if result == 0 {
            pthread_detach(thread)
        } else {
            unmanaged.release()
        }
        return result
        #endif
    }

    private func runReceiveLoop() {
        var terminalError: DatagramError?

        receiveLoop: while true {
            let snapshot: WorkerSnapshot? = state.withLock { state in
                guard case .open = state.lifecycle else {
                    return nil
                }
                return WorkerSnapshot(
                    socketDescriptor: state.socketDescriptor,
                    wakeDescriptor: state.wakeReadDescriptor
                )
            }
            guard let snapshot else { break }

            var descriptors = [
                pollfd(
                    fd: snapshot.socketDescriptor,
                    events: Int16(POLLIN),
                    revents: 0
                ),
                pollfd(
                    fd: snapshot.wakeDescriptor,
                    events: Int16(POLLIN),
                    revents: 0
                ),
            ]
            let pollResult = poll(&descriptors, 2, -1)
            if pollResult < 0 {
                let code = posixErrno
                if code == EINTR { continue }
                terminalError = .backendFailure(
                    operation: .receive,
                    code: Int(code),
                    terminal: true
                )
                break
            }

            if (descriptors[1].revents & Int16(POLLIN | POLLERR | POLLHUP | POLLNVAL)) != 0 {
                break
            }
            if (descriptors[0].revents & Int16(POLLERR | POLLHUP | POLLNVAL)) != 0 {
                let shutdownRequested = state.withLock {
                    if case .shutdownRequested = $0.lifecycle { return true }
                    return false
                }
                if shutdownRequested { break }
                terminalError = .backendFailure(
                    operation: .receive,
                    code: Int(EIO),
                    terminal: true
                )
                break
            }
            guard (descriptors[0].revents & Int16(POLLIN)) != 0 else {
                continue
            }

            switch receiveOnce(descriptor: snapshot.socketDescriptor) {
            case let .datagram(datagram):
                if let error = accept(datagram) {
                    terminalError = error
                    break receiveLoop
                }
            case .oversized:
                recordOversizedDatagram()
            case .retry:
                continue
            case let .failure(error):
                terminalError = error
                break receiveLoop
            }
        }

        finishWorker(error: terminalError)
    }

    private func receiveOnce(descriptor: Int32) -> ReceiveOutcome {
        var storage = sockaddr_storage()
        var buffer = [UInt8](
            repeating: 0,
            count: receiveBufferSize
        )
        var message = msghdr()
        var vector = iovec()

        let received: Int = buffer.withUnsafeMutableBytes { rawBuffer in
            vector.iov_base = rawBuffer.baseAddress
            vector.iov_len = rawBuffer.count
            return withUnsafeMutablePointer(to: &storage) { storagePointer in
                withUnsafeMutablePointer(to: &vector) { vectorPointer in
                    message.msg_name = UnsafeMutableRawPointer(storagePointer)
                    message.msg_namelen = socklen_t(MemoryLayout<sockaddr_storage>.size)
                    message.msg_iov = vectorPointer
                    message.msg_iovlen = 1
                    return recvmsg(descriptor, &message, 0)
                }
            }
        }

        if received < 0 {
            let code = posixErrno
            if code == EINTR || code == EAGAIN || code == EWOULDBLOCK {
                return .retry
            }
            return .failure(
                .backendFailure(
                    operation: .receive,
                    code: Int(code),
                    terminal: true
                )
            )
        }

        if (Int(message.msg_flags) & Int(MSG_TRUNC)) != 0
            || received > receiveBufferSize {
            return .oversized
        }
        guard let source = POSIXSocketAddressCodec.decode(storage) else {
            return .failure(.invalidEndpoint)
        }

        buffer.removeLast(buffer.count - received)
        return .datagram(
            InboundDatagram(
                payload: OwnedBytes(consuming: buffer),
                source: source
            )
        )
    }

    private func accept(_ datagram: InboundDatagram) -> DatagramError? {
        var continuation: ReceiveContinuation?
        let terminalError: DatagramError? = state.withLock { state in
            guard case .open = state.lifecycle else {
                return nil
            }
            Self.increment(&state.receivedDatagramCount)

            if let waiter = state.receiveWaiter {
                state.receiveWaiter = nil
                continuation = waiter.continuation
                return nil
            }
            if state.queue.enqueue(datagram) {
                return nil
            }

            Self.increment(&state.droppedDatagramCount)
            switch state.overflowPolicy {
            case .dropNewest:
                return nil
            case .dropOldest:
                _ = state.queue.dequeue()
                precondition(state.queue.enqueue(datagram))
                return nil
            case .failTransport:
                return .receiveQueueOverflow(capacity: state.queue.capacity)
            }
        }

        continuation?.resume(returning: .success(datagram))
        return terminalError
    }

    private func recordOversizedDatagram() {
        state.withLock { state in
            guard case .open = state.lifecycle else { return }
            Self.increment(&state.receivedDatagramCount)
            Self.increment(&state.droppedDatagramCount)
        }
    }

    private func finishWorker(error: DatagramError?) {
        var receiveContinuation: ReceiveContinuation?
        let finalization: FinalizationActions? = state.withLock { state in
            let terminalError: DatagramError?
            switch state.lifecycle {
            case .open:
                terminalError = error
            case let .shutdownRequested(requestedError):
                terminalError = requestedError
            case let .terminal(existingError):
                terminalError = existingError
            }
            state.lifecycle = .terminal(terminalError)
            state.workerExited = true
            state.queue.removeAll()
            receiveContinuation = state.receiveWaiter?.continuation
            state.receiveWaiter = nil
            return Self.makeFinalizationActionsIfReady(state: &state)
        }

        if let error {
            receiveContinuation?.resume(returning: .failure(error))
        } else {
            receiveContinuation?.resume(returning: .success(nil))
        }
        finalization?.perform()
    }

    private func wakeWorker(
        wakeDescriptor: Int32,
        socketDescriptor: Int32
    ) {
        guard wakeDescriptor >= 0 else { return }
        var byte: UInt8 = 1
        var result: Int
        repeat {
            result = withUnsafePointer(to: &byte) {
                posixWrite(wakeDescriptor, buffer: $0, length: 1)
            }
        } while result < 0 && posixErrno == EINTR

        guard result == 1 else {
            let code = posixErrno
            state.withLock { state in
                if case .shutdownRequested = state.lifecycle {
                    state.lifecycle = .shutdownRequested(
                        .backendFailure(
                            operation: .shutdown,
                            code: Int(code),
                            terminal: true
                        )
                    )
                }
            }
            if socketDescriptor >= 0 {
                _ = posixShutdown(socketDescriptor)
            }
            return
        }
    }

    private static func makeFinalizationActionsIfReady(
        state: inout SocketState
    ) -> FinalizationActions? {
        guard state.workerExited,
              state.activeDescriptorOperationCount == 0,
              !state.finalized,
              case let .terminal(error) = state.lifecycle
        else {
            return nil
        }

        state.finalized = true
        let waiters = state.shutdownWaiters
        state.shutdownWaiters.removeAll(keepingCapacity: false)
        return FinalizationActions(
            descriptors: state.takeDescriptors(),
            shutdownWaiters: waiters,
            shutdownResult: shutdownResult(error)
        )
    }

    private static func shutdownResult(_ error: DatagramError?) -> ShutdownResult {
        if let error {
            return .failure(error)
        }
        return .success(())
    }

    private static func increment(_ value: inout UInt64) {
        if value < UInt64.max {
            value += 1
        }
    }

    private static func ipv4Address(
        for interface: NetworkInterfaceIndex
    ) -> in_addr? {
        var firstAddress: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&firstAddress) == 0 else { return nil }
        defer { freeifaddrs(firstAddress) }

        var cursor = firstAddress
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }
            guard let name = current.pointee.ifa_name,
                  if_nametoindex(name) == interface.rawValue,
                  let address = current.pointee.ifa_addr,
                  Int32(address.pointee.sa_family) == AF_INET
            else {
                continue
            }
            return UnsafeRawPointer(address)
                .assumingMemoryBound(to: sockaddr_in.self)
                .pointee
                .sin_addr
        }
        return nil
    }

    private static func setMulticastInterface(
        descriptor: Int32,
        interface: NetworkInterfaceIndex,
        family: IPAddressFamily
    ) throws(DatagramError) {
        let result: Int32
        switch family {
        case .ipv4:
            guard var address = ipv4Address(for: interface) else {
                throw .invalidEndpoint
            }
            result = posixSetSocketOption(
                descriptor,
                level: Int32(IPPROTO_IP),
                option: Int32(IP_MULTICAST_IF),
                value: &address,
                length: socklen_t(MemoryLayout<in_addr>.size)
            )
        case .ipv6:
            var index = interface.rawValue
            result = posixSetSocketOption(
                descriptor,
                level: Int32(IPPROTO_IPV6),
                option: Int32(IPV6_MULTICAST_IF),
                value: &index,
                length: socklen_t(MemoryLayout<UInt32>.size)
            )
        }

        guard result == 0 else {
            throw .backendFailure(
                operation: .multicast,
                code: Int(posixErrno),
                terminal: false
            )
        }
    }
}

private enum ReceiveOutcome {
    case datagram(InboundDatagram)
    case oversized
    case retry
    case failure(DatagramError)
}

private enum SocketLifecycle: Sendable {
    case open
    case shutdownRequested(DatagramError?)
    case terminal(DatagramError?)
}

private struct ReceiveWaiter: Sendable {
    let token: UInt64
    let continuation: ReceiveContinuation
}

private struct SocketState: Sendable {
    var socketDescriptor: Int32
    var wakeReadDescriptor: Int32
    var wakeWriteDescriptor: Int32
    var lifecycle: SocketLifecycle = .open
    var workerExited = false
    var finalized = false
    var activeDescriptorOperationCount = 0
    var nextReceiveToken: UInt64 = 1
    var reservedReceiveTokens: Set<UInt64> = []
    var cancelledReceiveTokens: Set<UInt64> = []
    var receiveWaiter: ReceiveWaiter?
    var shutdownWaiters: [ShutdownContinuation] = []
    var queue: DatagramQueue
    let overflowPolicy: DatagramOverflowPolicy
    var receivedDatagramCount: UInt64 = 0
    var droppedDatagramCount: UInt64 = 0

    mutating func takeDescriptors() -> DescriptorSet {
        let descriptors = DescriptorSet(
            socketDescriptor: socketDescriptor,
            wakeReadDescriptor: wakeReadDescriptor,
            wakeWriteDescriptor: wakeWriteDescriptor
        )
        socketDescriptor = -1
        wakeReadDescriptor = -1
        wakeWriteDescriptor = -1
        return descriptors
    }
}

private struct DatagramQueue: Sendable {
    private var storage: [InboundDatagram?]
    private var head = 0
    private(set) var count = 0

    let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
        storage = Array(repeating: nil, count: capacity)
    }

    mutating func enqueue(_ datagram: InboundDatagram) -> Bool {
        guard count < capacity else { return false }
        let index = (head + count) % capacity
        storage[index] = datagram
        count += 1
        return true
    }

    mutating func dequeue() -> InboundDatagram? {
        guard count > 0 else { return nil }
        let datagram = storage[head]
        storage[head] = nil
        head = (head + 1) % capacity
        count -= 1
        return datagram
    }

    mutating func removeAll() {
        while dequeue() != nil {}
    }
}

private struct WorkerSnapshot: Sendable {
    let socketDescriptor: Int32
    let wakeDescriptor: Int32
}

private struct DescriptorSet: Sendable {
    let socketDescriptor: Int32
    let wakeReadDescriptor: Int32
    let wakeWriteDescriptor: Int32

    init(
        socketDescriptor: Int32 = -1,
        wakeReadDescriptor: Int32 = -1,
        wakeWriteDescriptor: Int32 = -1
    ) {
        self.socketDescriptor = socketDescriptor
        self.wakeReadDescriptor = wakeReadDescriptor
        self.wakeWriteDescriptor = wakeWriteDescriptor
    }

    func close() {
        if socketDescriptor >= 0 { _ = posixClose(socketDescriptor) }
        if wakeReadDescriptor >= 0 { _ = posixClose(wakeReadDescriptor) }
        if wakeWriteDescriptor >= 0 { _ = posixClose(wakeWriteDescriptor) }
    }
}

private struct FinalizationActions: Sendable {
    let descriptors: DescriptorSet
    let shutdownWaiters: [ShutdownContinuation]
    let shutdownResult: ShutdownResult

    func perform() {
        descriptors.close()
        for continuation in shutdownWaiters {
            continuation.resume(returning: shutdownResult)
        }
    }
}

private struct ShutdownRegistrationActions: Sendable {
    let receiveContinuation: ReceiveContinuation?
    let immediateResult: ShutdownResult?
    let shouldWakeWorker: Bool
    let wakeDescriptor: Int32
    let socketDescriptor: Int32

    init(
        receiveContinuation: ReceiveContinuation? = nil,
        immediateResult: ShutdownResult? = nil,
        shouldWakeWorker: Bool = false,
        wakeDescriptor: Int32 = -1,
        socketDescriptor: Int32 = -1
    ) {
        self.receiveContinuation = receiveContinuation
        self.immediateResult = immediateResult
        self.shouldWakeWorker = shouldWakeWorker
        self.wakeDescriptor = wakeDescriptor
        self.socketDescriptor = socketDescriptor
    }
}

#endif
