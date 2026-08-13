import NetworkingCore

/// Optional multicast membership capability for a datagram transport.
public protocol MulticastMembershipManaging: DatagramTransport {
    func join(
        group: IPAddress,
        interface: NetworkInterfaceIndex?
    ) async throws(DatagramError)

    func leave(
        group: IPAddress,
        interface: NetworkInterfaceIndex?
    ) async throws(DatagramError)

    func configureMulticast(
        _ configuration: MulticastConfiguration,
        for family: IPAddressFamily
    ) async throws(DatagramError)
}
