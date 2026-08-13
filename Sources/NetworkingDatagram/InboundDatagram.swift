import NetworkingCore

/// One received datagram with an owning payload and packet metadata.
public struct InboundDatagram: Sendable, Hashable {
    public let payload: OwnedBytes
    public let source: IPSocketEndpoint
    public let metadata: DatagramReceiveMetadata

    public init(
        payload: consuming OwnedBytes,
        source: IPSocketEndpoint,
        metadata: DatagramReceiveMetadata = DatagramReceiveMetadata()
    ) {
        self.payload = payload
        self.source = source
        self.metadata = metadata
    }
}
