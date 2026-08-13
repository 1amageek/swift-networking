/// An IP address, transport port, and optional IPv6 scope.
public struct IPSocketEndpoint: Sendable, Hashable {
    public let address: IPAddress
    public let port: UInt16
    public let scopeID: NetworkInterfaceIndex?

    public init(
        address: IPAddress,
        port: UInt16,
        scopeID: NetworkInterfaceIndex? = nil
    ) throws(NetworkAddressError) {
        if address.isIPv4, scopeID != nil {
            throw .scopeRequiresIPv6
        }
        self.address = address
        self.port = port
        self.scopeID = scopeID
    }

    @inlinable
    public init(ipv4 a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8, port: UInt16) {
        address = .v4(a, b, c, d)
        self.port = port
        scopeID = nil
    }

    @inlinable
    public init(
        ipv6 address: InlineIPv6Address,
        port: UInt16,
        scopeID: NetworkInterfaceIndex? = nil
    ) {
        self.address = .v6(address)
        self.port = port
        self.scopeID = scopeID
    }
}
