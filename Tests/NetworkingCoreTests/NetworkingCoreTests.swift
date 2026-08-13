import XCTest
import NetworkingCore

final class NetworkingCoreTests: XCTestCase {
    func testOwnedBytesBorrowsStableContiguousStorage() {
        let source = ContiguousArray((0..<4_096).map { UInt8(truncatingIfNeeded: $0) })
        let sourceAddress = source.withUnsafeBytes { UInt(bitPattern: $0.baseAddress) }
        let bytes = OwnedBytes(consuming: source)

        let firstAddress = bytes.withBorrowedBytes { span in
            span.bytes.withUnsafeBytes { UInt(bitPattern: $0.baseAddress) }
        }
        let secondAddress = bytes.withBorrowedBytes { span in
            span.bytes.withUnsafeBytes { UInt(bitPattern: $0.baseAddress) }
        }

        XCTAssertNotEqual(firstAddress, 0)
        XCTAssertEqual(firstAddress, sourceAddress)
        XCTAssertEqual(firstAddress, secondAddress)
    }

    func testOwnedBytesConsumesArrayStorageWithoutCopying() {
        let source = [UInt8](repeating: 0xA5, count: 4_096)
        let sourceAddress = source.withUnsafeBytes { UInt(bitPattern: $0.baseAddress) }

        let bytes = OwnedBytes(consuming: source)
        let ownedAddress = bytes.withBorrowedBytes { span in
            span.bytes.withUnsafeBytes { UInt(bitPattern: $0.baseAddress) }
        }

        XCTAssertNotEqual(sourceAddress, 0)
        XCTAssertEqual(ownedAddress, sourceAddress)
    }

    func testBorrowedCursorReadsWithoutMaterializingSlices() throws {
        let source: ContiguousArray<UInt8> = [0x12, 0x34, 0x56, 0x78]
        var cursor = ByteCursor(source.span)
        XCTAssertEqual(try cursor.readUInt16BigEndian(), 0x1234)
        let suffix = try cursor.readSpan(count: 2)
        XCTAssertEqual(suffix[0], 0x56)
        XCTAssertEqual(suffix[1], 0x78)
        XCTAssertNoThrow(try cursor.requireFullyConsumed())
    }

    func testFailedReadsDoNotAdvanceTheCursor() throws {
        let source: ContiguousArray<UInt8> = [1, 2]
        var cursor = ByteCursor(source.span)
        do {
            _ = try cursor.readSpan(count: 3)
            XCTFail("An out-of-bounds read succeeded")
        } catch let error {
            XCTAssertEqual(
                error,
                .outOfBounds(offset: 0, requested: 3, available: 2)
            )
        }
        XCTAssertEqual(cursor.offset, 0)
        XCTAssertEqual(try cursor.readUInt16BigEndian(), 0x0102)
    }

    func testBuilderRejectsCapacityOverflowBeforeMutation() throws {
        var builder = try ByteBuilder(maximumByteCount: 2)
        try builder.append(0xAA)
        let source: ContiguousArray<UInt8> = [0xBB, 0xCC]
        XCTAssertThrowsError(try builder.append(source.span)) { error in
            XCTAssertEqual(
                error as? ByteError,
                .capacityExceeded(limit: 2, attempted: 3)
            )
        }
        XCTAssertEqual(builder.count, 1)
    }

    func testIPv6ScopeCannotBeAttachedToIPv4() throws {
        let interface = try NetworkInterfaceIndex(rawValue: 1)
        XCTAssertThrowsError(
            try IPSocketEndpoint(
                address: .v4(127, 0, 0, 1),
                port: 443,
                scopeID: interface
            )
        ) { error in
            XCTAssertEqual(error as? NetworkAddressError, .scopeRequiresIPv6)
        }
    }

    func testNumericIPAddressTextRoundTrips() throws {
        let cases = [
            "127.0.0.1",
            "::",
            "::1",
            "2001:db8::1",
            "2001:db8:0:1:2:3:4:5",
            "::ffff:192.0.2.1",
            "1:2:3:4:5:6:192.0.2.1",
        ]
        for text in cases {
            let address = try XCTUnwrap(IPAddress(parsing: text))
            XCTAssertEqual(IPAddress(parsing: address.textRepresentation), address)
        }
    }

    func testNumericIPAddressParserRejectsMalformedInput() {
        let malformed = [
            "",
            "127.0.0",
            "256.0.0.1",
            "2001::db8::1",
            ":::",
            "1:::2",
            "1:2:3:4:5:6:7",
            "1:2:3:4:5:6:7:8:9",
            "1:2:3:4:5:192.0.2.1",
            "::ffff:999.0.2.1",
            "::ffff:192.0.2.1:3",
            "fe80::1%en0",
        ]
        for text in malformed {
            XCTAssertNil(IPAddress(parsing: text), "Unexpectedly parsed \(text)")
        }
    }
}
