import NetworkingCore

/// Packet metadata reported by a capable backend.
public struct DatagramReceiveMetadata: Sendable, Hashable {
    public let destination: IPSocketEndpoint?
    public let interfaceIndex: NetworkInterfaceIndex?
    public let explicitCongestionNotification: ExplicitCongestionNotification?

    public init(
        destination: IPSocketEndpoint? = nil,
        interfaceIndex: NetworkInterfaceIndex? = nil,
        explicitCongestionNotification: ExplicitCongestionNotification? = nil
    ) {
        self.destination = destination
        self.interfaceIndex = interfaceIndex
        self.explicitCongestionNotification = explicitCongestionNotification
    }
}
