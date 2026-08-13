import NetworkingCore

/// Connectionless datagram I/O with explicit ownership and lifecycle semantics.
///
/// Exactly one `receive()` operation may be active. A second concurrent call
/// fails with `DatagramError.concurrentReceive`. Cancellation terminates only
/// the active receive and leaves the transport usable. `nil` means clean
/// shutdown; backend failures are always thrown.
///
/// Transports have reference identity because they own one I/O lifecycle. A
/// connection may retain a transport, but independent receive loops must never
/// share the same instance unless a demultiplexer is the sole receive owner.
public protocol DatagramTransport: AnyObject, Sendable {
    var localEndpoint: IPSocketEndpoint { get }
    var maximumDatagramSize: Int { get }
    var capabilities: DatagramTransportCapabilities { get }
    var receiveBuffering: DatagramReceiveBuffering { get }

    /// Transfers an owning payload to the backend.
    ///
    /// Success means the backend accepted the datagram, not that the peer
    /// received it.
    func send(
        _ payload: consuming OwnedBytes,
        to endpoint: IPSocketEndpoint,
        metadata: DatagramSendMetadata
    ) async throws(DatagramError)

    func receive() async throws(DatagramError) -> InboundDatagram?

    func receiveStatistics() -> DatagramReceiveStatistics

    /// Shuts down the transport.
    ///
    /// Concurrent and repeated calls join the same teardown operation and
    /// observe the same terminal result.
    func shutdown() async throws(DatagramError)
}

extension DatagramTransport {
    public func send(
        _ payload: consuming OwnedBytes,
        to endpoint: IPSocketEndpoint
    ) async throws(DatagramError) {
        try await send(payload, to: endpoint, metadata: DatagramSendMetadata())
    }
}
