import NetworkingCore

/// Optional controls for one outbound datagram.
public struct DatagramSendMetadata: Sendable, Hashable {
    public let sourceAddress: IPAddress?
    public let interfaceIndex: NetworkInterfaceIndex?
    public let explicitCongestionNotification: ExplicitCongestionNotification?

    public init(
        sourceAddress: IPAddress? = nil,
        interfaceIndex: NetworkInterfaceIndex? = nil,
        explicitCongestionNotification: ExplicitCongestionNotification? = nil
    ) {
        self.sourceAddress = sourceAddress
        self.interfaceIndex = interfaceIndex
        self.explicitCongestionNotification = explicitCongestionNotification
    }

    public var requiredCapabilities: DatagramTransportCapabilities {
        var result: DatagramTransportCapabilities = []
        if sourceAddress != nil {
            result.insert(.sourceAddressSelection)
        }
        if interfaceIndex != nil {
            result.insert(.interfaceIndex)
        }
        if explicitCongestionNotification != nil {
            result.insert(.explicitCongestionNotification)
        }
        return result
    }
}
