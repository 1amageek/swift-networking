#if canImport(Darwin) || canImport(Glibc) || canImport(Musl)

import _Concurrency
import NetworkingCore
import NetworkingDatagram

/// A raw POSIX UDP transport with bounded receive buffering.
public final class POSIXDatagramTransport: MulticastMembershipManaging, Sendable {
    private let socket: POSIXDatagramSocket

    public let localEndpoint: IPSocketEndpoint
    public let maximumDatagramSize: Int
    public let receiveBuffering: DatagramReceiveBuffering
    public let capabilities: DatagramTransportCapabilities = [.multicastMembership]

    public convenience init(
        bindingTo endpoint: IPSocketEndpoint,
        maximumDatagramSize: Int = 65_507,
        receiveBuffering: DatagramReceiveBuffering,
        reuseForMulticast: Bool = false
    ) throws(DatagramError) {
        try self.init(
            bindingTo: endpoint,
            maximumDatagramSize: maximumDatagramSize,
            receiveBuffering: receiveBuffering,
            reuseForMulticast: reuseForMulticast,
            receiveRegistrationObserver: nil
        )
    }

    init(
        bindingTo endpoint: IPSocketEndpoint,
        maximumDatagramSize: Int,
        receiveBuffering: DatagramReceiveBuffering,
        reuseForMulticast: Bool,
        receiveRegistrationObserver: (@Sendable () -> Void)?
    ) throws(DatagramError) {
        guard maximumDatagramSize > 0, maximumDatagramSize <= 65_535 else {
            throw .invalidBufferCapacity(maximumDatagramSize)
        }
        let socket = try POSIXDatagramSocket(
            bindingTo: endpoint,
            receiveBufferSize: maximumDatagramSize,
            receiveBuffering: receiveBuffering,
            reuseForMulticast: reuseForMulticast,
            receiveRegistrationObserver: receiveRegistrationObserver
        )
        self.socket = socket
        self.localEndpoint = try socket.boundEndpoint()
        self.maximumDatagramSize = maximumDatagramSize
        self.receiveBuffering = receiveBuffering
    }

    public convenience init(
        bindingTo endpoint: IPSocketEndpoint,
        maximumDatagramSize: Int = 65_507,
        receiveQueueCapacity: Int = 64,
        overflowPolicy: DatagramOverflowPolicy = .dropNewest,
        reuseForMulticast: Bool = false
    ) throws(DatagramError) {
        let buffering = try DatagramReceiveBuffering(
            capacity: receiveQueueCapacity,
            overflowPolicy: overflowPolicy
        )
        try self.init(
            bindingTo: endpoint,
            maximumDatagramSize: maximumDatagramSize,
            receiveBuffering: buffering,
            reuseForMulticast: reuseForMulticast
        )
    }

    public func send(
        _ payload: consuming OwnedBytes,
        to endpoint: IPSocketEndpoint,
        metadata: DatagramSendMetadata
    ) async throws(DatagramError) {
        guard payload.count <= maximumDatagramSize else {
            throw .messageTooLarge(
                size: payload.count,
                maximum: maximumDatagramSize
            )
        }
        let unsupported = metadata.requiredCapabilities.subtracting(capabilities)
        guard unsupported.isEmpty else {
            throw .unsupportedCapability(unsupported)
        }
        try socket.send(payload, to: endpoint)
    }

    public func receive() async throws(DatagramError) -> InboundDatagram? {
        let token = socket.reserveReceiveToken()
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                socket.registerReceive(token: token, continuation: continuation)
            }
        } onCancel: {
            socket.cancelReceive(token: token)
        }
        return try result.get()
    }

    public func receiveStatistics() -> DatagramReceiveStatistics {
        socket.statistics()
    }

    public func join(
        group: IPAddress,
        interface: NetworkInterfaceIndex?
    ) async throws(DatagramError) {
        try socket.setMembership(group: group, interface: interface, join: true)
    }

    public func leave(
        group: IPAddress,
        interface: NetworkInterfaceIndex?
    ) async throws(DatagramError) {
        try socket.setMembership(group: group, interface: interface, join: false)
    }

    public func configureMulticast(
        _ configuration: MulticastConfiguration,
        for family: IPAddressFamily
    ) async throws(DatagramError) {
        try socket.configureMulticast(configuration, for: family)
    }

    public func shutdown() async throws(DatagramError) {
        let result = await withCheckedContinuation { continuation in
            socket.registerShutdown(continuation)
        }
        return try result.get()
    }

    deinit {
        socket.requestShutdownWithoutWaiting()
    }
}

#endif
