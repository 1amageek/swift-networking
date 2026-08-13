extension IPAddress {
    /// Parses an IPv4 or IPv6 numeric address without DNS resolution.
    public init?(parsing text: String) {
        if let ipv4 = Self.parseIPv4(text) {
            self = ipv4
            return
        }
        guard let ipv6 = Self.parseIPv6(text) else { return nil }
        self = .v6(ipv6)
    }

    /// Returns a canonical numeric representation suitable for wire-adjacent APIs.
    public var textRepresentation: String {
        switch self {
        case let .v4(a, b, c, d):
            return "\(a).\(b).\(c).\(d)"
        case let .v6(address):
            let bytes = address.toContiguousArray()
            var groups = [UInt16]()
            groups.reserveCapacity(8)
            for offset in stride(from: 0, to: 16, by: 2) {
                groups.append((UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1]))
            }
            let zeroRun = Self.longestZeroRun(in: groups)
            if let zeroRun {
                let left = groups[..<zeroRun.lowerBound]
                    .map { String($0, radix: 16) }
                    .joined(separator: ":")
                let right = groups[zeroRun.upperBound...]
                    .map { String($0, radix: 16) }
                    .joined(separator: ":")
                if left.isEmpty && right.isEmpty { return "::" }
                if left.isEmpty { return "::" + right }
                if right.isEmpty { return left + "::" }
                return left + "::" + right
            }
            return groups.map { String($0, radix: 16) }.joined(separator: ":")
        }
    }

    private static func parseIPv4(_ text: String) -> IPAddress? {
        let bytes = ContiguousArray(text.utf8)
        guard let octets = parseIPv4Bytes(bytes, in: 0..<bytes.count) else {
            return nil
        }
        return .v4(octets[0], octets[1], octets[2], octets[3])
    }

    private static func parseIPv6(_ text: String) -> InlineIPv6Address? {
        let bytes = ContiguousArray(text.utf8)
        guard !bytes.isEmpty else { return nil }

        var compressionOffset: Int?
        var index = 0
        while index < bytes.count {
            guard bytes[index] != 0x25 else { return nil }
            if bytes[index] == 0x3A,
               index + 1 < bytes.count,
               bytes[index + 1] == 0x3A {
                guard compressionOffset == nil else { return nil }
                compressionOffset = index
                index += 2
            } else {
                index += 1
            }
        }

        let leftRange = 0..<(compressionOffset ?? bytes.count)
        let rightRange = compressionOffset.map { ($0 + 2)..<bytes.count }
            ?? bytes.count..<bytes.count
        guard let left = parseIPv6Groups(bytes, in: leftRange),
              let right = parseIPv6Groups(bytes, in: rightRange) else {
            return nil
        }

        var groups: [UInt16]
        if compressionOffset != nil {
            let missing = 8 - left.count - right.count
            guard missing > 0 else { return nil }
            groups = left + [UInt16](repeating: 0, count: missing) + right
        } else {
            guard left.count == 8 else { return nil }
            groups = left
        }
        guard groups.count == 8 else { return nil }

        var addressBytes = [UInt8]()
        addressBytes.reserveCapacity(16)
        for group in groups {
            addressBytes.append(UInt8(group >> 8))
            addressBytes.append(UInt8(group & 0xFF))
        }
        return InlineIPv6Address(
            addressBytes[0], addressBytes[1], addressBytes[2], addressBytes[3],
            addressBytes[4], addressBytes[5], addressBytes[6], addressBytes[7],
            addressBytes[8], addressBytes[9], addressBytes[10], addressBytes[11],
            addressBytes[12], addressBytes[13], addressBytes[14], addressBytes[15]
        )
    }

    private static func parseIPv6Groups(
        _ bytes: ContiguousArray<UInt8>,
        in range: Range<Int>
    ) -> [UInt16]? {
        if range.isEmpty { return [] }
        var groups = [UInt16]()
        groups.reserveCapacity(8)
        var componentStart = range.lowerBound
        var cursor = range.lowerBound
        while cursor <= range.upperBound {
            if cursor == range.upperBound || bytes[cursor] == 0x3A {
                guard componentStart < cursor else { return nil }
                let componentRange = componentStart..<cursor
                if containsByte(0x2E, in: bytes, range: componentRange) {
                    guard cursor == range.upperBound,
                          let octets = parseIPv4Bytes(bytes, in: componentRange) else {
                        return nil
                    }
                    groups.append((UInt16(octets[0]) << 8) | UInt16(octets[1]))
                    groups.append((UInt16(octets[2]) << 8) | UInt16(octets[3]))
                } else {
                    guard componentRange.count <= 4 else { return nil }
                    var value: UInt16 = 0
                    for byte in bytes[componentRange] {
                        guard let digit = hexadecimalDigit(byte) else { return nil }
                        value = (value << 4) | UInt16(digit)
                    }
                    groups.append(value)
                }
                componentStart = cursor + 1
            }
            cursor += 1
        }
        return groups
    }

    private static func parseIPv4Bytes(
        _ bytes: ContiguousArray<UInt8>,
        in range: Range<Int>
    ) -> [UInt8]? {
        guard !range.isEmpty else { return nil }
        var octets = [UInt8]()
        octets.reserveCapacity(4)
        var value = 0
        var digitCount = 0
        var index = range.lowerBound
        while index <= range.upperBound {
            if index == range.upperBound || bytes[index] == 0x2E {
                guard digitCount > 0, value <= Int(UInt8.max) else { return nil }
                octets.append(UInt8(value))
                value = 0
                digitCount = 0
            } else {
                let byte = bytes[index]
                guard byte >= 0x30, byte <= 0x39 else { return nil }
                value = value * 10 + Int(byte - 0x30)
                digitCount += 1
                guard digitCount <= 3, value <= Int(UInt8.max) else { return nil }
            }
            index += 1
        }
        return octets.count == 4 ? octets : nil
    }

    private static func containsByte(
        _ needle: UInt8,
        in bytes: ContiguousArray<UInt8>,
        range: Range<Int>
    ) -> Bool {
        for index in range where bytes[index] == needle {
            return true
        }
        return false
    }

    private static func hexadecimalDigit(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 0x30...0x39:
            return byte - 0x30
        case 0x41...0x46:
            return byte - 0x41 + 10
        case 0x61...0x66:
            return byte - 0x61 + 10
        default:
            return nil
        }
    }

    private static func longestZeroRun(
        in groups: [UInt16]
    ) -> Range<Int>? {
        var bestStart = 0
        var bestCount = 0
        var index = 0
        while index < groups.count {
            guard groups[index] == 0 else {
                index += 1
                continue
            }
            let start = index
            while index < groups.count, groups[index] == 0 {
                index += 1
            }
            let count = index - start
            if count > bestCount {
                bestStart = start
                bestCount = count
            }
        }
        guard bestCount >= 2 else { return nil }
        return bestStart..<(bestStart + bestCount)
    }
}
