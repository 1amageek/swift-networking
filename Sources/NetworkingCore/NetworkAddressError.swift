public enum NetworkAddressError: Error, Sendable, Equatable {
    case zeroInterfaceIndex
    case scopeRequiresIPv6
}
