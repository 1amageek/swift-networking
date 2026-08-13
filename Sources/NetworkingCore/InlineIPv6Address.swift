/// A fixed-size IPv6 address payload stored in network byte order.
public struct InlineIPv6Address: Sendable, Hashable {
    public var b0: UInt8
    public var b1: UInt8
    public var b2: UInt8
    public var b3: UInt8
    public var b4: UInt8
    public var b5: UInt8
    public var b6: UInt8
    public var b7: UInt8
    public var b8: UInt8
    public var b9: UInt8
    public var b10: UInt8
    public var b11: UInt8
    public var b12: UInt8
    public var b13: UInt8
    public var b14: UInt8
    public var b15: UInt8

    @inlinable
    public init(
        _ b0: UInt8, _ b1: UInt8, _ b2: UInt8, _ b3: UInt8,
        _ b4: UInt8, _ b5: UInt8, _ b6: UInt8, _ b7: UInt8,
        _ b8: UInt8, _ b9: UInt8, _ b10: UInt8, _ b11: UInt8,
        _ b12: UInt8, _ b13: UInt8, _ b14: UInt8, _ b15: UInt8
    ) {
        self.b0 = b0
        self.b1 = b1
        self.b2 = b2
        self.b3 = b3
        self.b4 = b4
        self.b5 = b5
        self.b6 = b6
        self.b7 = b7
        self.b8 = b8
        self.b9 = b9
        self.b10 = b10
        self.b11 = b11
        self.b12 = b12
        self.b13 = b13
        self.b14 = b14
        self.b15 = b15
    }

    @inlinable
    public func toContiguousArray() -> ContiguousArray<UInt8> {
        [
            b0, b1, b2, b3, b4, b5, b6, b7,
            b8, b9, b10, b11, b12, b13, b14, b15,
        ]
    }
}
