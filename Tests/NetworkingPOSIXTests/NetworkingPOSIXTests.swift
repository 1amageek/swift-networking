#if canImport(Darwin) || canImport(Glibc) || canImport(Musl)

import XCTest
import NetworkingCore
import NetworkingDatagram
@testable import NetworkingPOSIX
import NetworkingTime

final class NetworkingPOSIXTests: XCTestCase {
    func testMonotonicReadsShareOneDomain() throws {
        let clock = POSIXMonotonicClock()
        let first = try clock.now()
        let second = try clock.now()
        XCTAssertEqual(first.clockIdentifier, second.clockIdentifier)
        XCTAssertGreaterThanOrEqual(try second.durationNanoseconds(since: first), 0)
    }

    func testWallClockReturnsARealUnixInstant() throws {
        let instant = try POSIXWallClock().now()
        XCTAssertGreaterThan(instant.secondsSinceUnixEpoch, 0)
    }

    func testPOSIXTimerSleepsOnItsMonotonicDomain() async throws {
        let timer = POSIXAsyncTimer()
        let start = try timer.now()
        let deadline = try start.advanced(byNanoseconds: 2_000_000)

        try await timer.sleep(until: deadline)

        let end = try timer.now()
        XCTAssertGreaterThanOrEqual(end.nanoseconds, deadline.nanoseconds)
    }

    func testPOSIXTimerCancellationIsExplicit() async throws {
        let timer = POSIXAsyncTimer()
        let deadline = try timer.now().advanced(byNanoseconds: 1_000_000_000)
        let task = Task {
            try await timer.sleep(until: deadline)
        }
        await Task.yield()
        task.cancel()

        do {
            try await task.value
            XCTFail("Cancelled timer unexpectedly succeeded")
        } catch let error as TimeError {
            XCTAssertEqual(error, .cancelled)
        }
    }

    func testPOSIXTimerHandlesManyConcurrentWaiters() async throws {
        let timer = POSIXAsyncTimer()
        let deadline = try timer.now().advanced(byNanoseconds: 5_000_000)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<128 {
                group.addTask {
                    try await timer.sleep(until: deadline)
                }
            }
            try await group.waitForAll()
        }

        XCTAssertGreaterThanOrEqual(try timer.now().nanoseconds, deadline.nanoseconds)
    }

    func testUDPDatagramTravelsThroughRealSocket() async throws {
        let receiver = try POSIXDatagramTransport(
            bindingTo: IPSocketEndpoint(ipv4: 127, 0, 0, 1, port: 0)
        )
        let sender = try POSIXDatagramTransport(
            bindingTo: IPSocketEndpoint(ipv4: 127, 0, 0, 1, port: 0)
        )
        let bytes = OwnedBytes(consuming: ContiguousArray([1, 2, 3, 4]))

        try await sender.send(bytes, to: receiver.localEndpoint)
        let received = try await receiver.receive()

        XCTAssertEqual(received?.payload, bytes)
        XCTAssertEqual(received?.source, sender.localEndpoint)
        XCTAssertEqual(receiver.receiveStatistics().receivedDatagramCount, 1)
        try await sender.shutdown()
        try await receiver.shutdown()
    }

    func testCancellationOnlyCancelsActiveReceive() async throws {
        let receiver = try POSIXDatagramTransport(
            bindingTo: IPSocketEndpoint(ipv4: 127, 0, 0, 1, port: 0)
        )
        let sender = try POSIXDatagramTransport(
            bindingTo: IPSocketEndpoint(ipv4: 127, 0, 0, 1, port: 0)
        )

        let pending = Task {
            try await receiver.receive()
        }
        await Task.yield()
        pending.cancel()

        do {
            _ = try await pending.value
            XCTFail("Cancelled receive unexpectedly succeeded")
        } catch let error as DatagramError {
            XCTAssertEqual(error, .cancelled)
        }

        let bytes = OwnedBytes(consuming: ContiguousArray([9, 8, 7]))
        try await sender.send(bytes, to: receiver.localEndpoint)
        let received = try await receiver.receive()
        XCTAssertEqual(received?.payload, bytes)
        try await sender.shutdown()
        try await receiver.shutdown()
    }

    func testConcurrentReceiveFailsExplicitly() async throws {
        let registration = ReceiveRegistrationSignal()
        let buffering = try DatagramReceiveBuffering(
            capacity: 64,
            overflowPolicy: .dropNewest
        )
        let transport = try POSIXDatagramTransport(
            bindingTo: IPSocketEndpoint(ipv4: 127, 0, 0, 1, port: 0),
            maximumDatagramSize: 65_507,
            receiveBuffering: buffering,
            reuseForMulticast: false,
            receiveRegistrationObserver: {
                Task {
                    await registration.signal()
                }
            }
        )
        let first = Task {
            try await transport.receive()
        }
        await registration.wait()

        do {
            _ = try await transport.receive()
            XCTFail("Concurrent receive unexpectedly succeeded")
        } catch let error {
            XCTAssertEqual(error, .concurrentReceive)
        }

        first.cancel()
        do {
            _ = try await first.value
            XCTFail("Cancelled first receive unexpectedly succeeded")
        } catch let error as DatagramError {
            XCTAssertEqual(error, .cancelled)
        }
        try await transport.shutdown()
    }

    func testDropNewestPolicyRecordsOverflow() async throws {
        let receiver = try POSIXDatagramTransport(
            bindingTo: IPSocketEndpoint(ipv4: 127, 0, 0, 1, port: 0),
            receiveQueueCapacity: 1,
            overflowPolicy: .dropNewest
        )
        let sender = try POSIXDatagramTransport(
            bindingTo: IPSocketEndpoint(ipv4: 127, 0, 0, 1, port: 0)
        )

        try await sender.send(
            OwnedBytes(consuming: ContiguousArray([1])),
            to: receiver.localEndpoint
        )
        try await sender.send(
            OwnedBytes(consuming: ContiguousArray([2])),
            to: receiver.localEndpoint
        )
        try await waitForReceivedCount(2, transport: receiver)

        XCTAssertEqual(receiver.receiveStatistics().droppedDatagramCount, 1)
        let received = try await receiver.receive()
        XCTAssertEqual(received?.payload[0], 1)
        try await sender.shutdown()
        try await receiver.shutdown()
    }

    func testFailTransportPolicySurfacesSameTerminalFailure() async throws {
        let receiver = try POSIXDatagramTransport(
            bindingTo: IPSocketEndpoint(ipv4: 127, 0, 0, 1, port: 0),
            receiveQueueCapacity: 1,
            overflowPolicy: .failTransport
        )
        let sender = try POSIXDatagramTransport(
            bindingTo: IPSocketEndpoint(ipv4: 127, 0, 0, 1, port: 0)
        )

        try await sender.send(
            OwnedBytes(consuming: ContiguousArray([1])),
            to: receiver.localEndpoint
        )
        try await sender.send(
            OwnedBytes(consuming: ContiguousArray([2])),
            to: receiver.localEndpoint
        )
        try await waitForReceivedCount(2, transport: receiver)

        let expected = DatagramError.receiveQueueOverflow(capacity: 1)
        do {
            _ = try await receiver.receive()
            XCTFail("Terminal receive unexpectedly succeeded")
        } catch let error {
            XCTAssertEqual(error, expected)
        }
        do {
            try await receiver.shutdown()
            XCTFail("Terminal shutdown unexpectedly succeeded")
        } catch let error {
            XCTAssertEqual(error, expected)
        }
        try await sender.shutdown()
    }

    func testShutdownIsIdempotentAndRetainsLocalEndpoint() async throws {
        let transport = try POSIXDatagramTransport(
            bindingTo: IPSocketEndpoint(ipv4: 127, 0, 0, 1, port: 0)
        )
        let endpoint = transport.localEndpoint

        async let first: Void = transport.shutdown()
        async let second: Void = transport.shutdown()
        _ = try await (first, second)

        XCTAssertEqual(transport.localEndpoint, endpoint)
        let received = try await transport.receive()
        XCTAssertNil(received)
        try await transport.shutdown()
    }

    func testUnsupportedSendMetadataFailsBeforeSyscall() async throws {
        let transport = try POSIXDatagramTransport(
            bindingTo: IPSocketEndpoint(ipv4: 127, 0, 0, 1, port: 0)
        )
        let metadata = DatagramSendMetadata(
            sourceAddress: .v4(127, 0, 0, 1)
        )

        do {
            try await transport.send(
                OwnedBytes(consuming: ContiguousArray([1])),
                to: transport.localEndpoint,
                metadata: metadata
            )
            XCTFail("Unsupported metadata unexpectedly succeeded")
        } catch let error {
            XCTAssertEqual(
                error,
                .unsupportedCapability([.sourceAddressSelection])
            )
        }
        try await transport.shutdown()
    }

    private func waitForReceivedCount(
        _ expectedCount: UInt64,
        transport: POSIXDatagramTransport
    ) async throws {
        for _ in 0..<100 {
            if transport.receiveStatistics().receivedDatagramCount >= expectedCount {
                return
            }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("Timed out waiting for UDP receive worker")
    }
}

private actor ReceiveRegistrationSignal {
    private var isSignalled = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        if isSignalled {
            return
        }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func signal() {
        isSignalled = true
        continuation?.resume()
        continuation = nil
    }
}

#endif
