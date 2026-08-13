import XCTest
import TLSTypes

final class TLSTypesTests: XCTestCase {
    func testALPNIsAnOpaqueBoundedOwnedValue() throws {
        var source: ContiguousArray<UInt8> = [0x68, 0x33]
        let value = try TLSApplicationProtocol(bytes: source)
        source[0] = 0
        let first = value.withBytes { $0[0] }
        XCTAssertEqual(first, 0x68)
        XCTAssertEqual(value.byteCount, 2)
    }

    func testTLSVocabularyRejectsEmptyServerNames() {
        XCTAssertThrowsError(try TLSServerName(bytes: [])) { error in
            XCTAssertEqual(error as? TLSVocabularyError, .invalidLength(actual: 0))
        }
    }
}
