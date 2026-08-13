import NetworkingCore

/// Outbound multicast behavior for one IP address family.
public struct MulticastConfiguration: Sendable, Hashable {
    public let hopLimit: UInt8
    public let loopbackEnabled: Bool
    public let interfaceIndex: NetworkInterfaceIndex?

    public init(
        hopLimit: UInt8,
        loopbackEnabled: Bool,
        interfaceIndex: NetworkInterfaceIndex? = nil
    ) {
        self.hopLimit = hopLimit
        self.loopbackEnabled = loopbackEnabled
        self.interfaceIndex = interfaceIndex
    }
}
