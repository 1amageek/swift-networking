/// A nonzero platform interface index.
public struct NetworkInterfaceIndex: Sendable, Hashable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) throws(NetworkAddressError) {
        guard rawValue != 0 else {
            throw .zeroInterfaceIndex
        }
        self.rawValue = rawValue
    }
}
