public struct DatagramTransportCapabilities: OptionSet, Sendable, Hashable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public static let receiveDestinationAddress = Self(rawValue: 1 << 0)
    public static let sourceAddressSelection = Self(rawValue: 1 << 1)
    public static let interfaceIndex = Self(rawValue: 1 << 2)
    public static let explicitCongestionNotification = Self(rawValue: 1 << 3)
    public static let multicastMembership = Self(rawValue: 1 << 4)
}
