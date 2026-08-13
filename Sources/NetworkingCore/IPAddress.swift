/// A Foundation-free IP address value.
public enum IPAddress: Sendable, Hashable {
    case v4(UInt8, UInt8, UInt8, UInt8)
    case v6(InlineIPv6Address)

    @inlinable
    public var isIPv4: Bool {
        if case .v4 = self {
            return true
        }
        return false
    }

    @inlinable
    public var isIPv6: Bool {
        !isIPv4
    }

    @inlinable
    public var family: IPAddressFamily {
        isIPv4 ? .ipv4 : .ipv6
    }

    @inlinable
    public var isMulticast: Bool {
        switch self {
        case let .v4(first, _, _, _):
            return (224...239).contains(first)
        case let .v6(bytes):
            return bytes.b0 == 0xFF
        }
    }

    @inlinable
    public func toContiguousArray() -> ContiguousArray<UInt8> {
        switch self {
        case let .v4(a, b, c, d):
            return [a, b, c, d]
        case let .v6(bytes):
            return bytes.toContiguousArray()
        }
    }
}
