import Foundation
import XCTest
import NetworkingCore
import NetworkingFoundationCompat
import NetworkingTime

final class NetworkingFoundationCompatTests: XCTestCase {
    func testDataBridgesCopyAtTheExplicitAdapterBoundary() {
        let source = Data([1, 2, 3])
        let owned = OwnedBytes(copying: source)
        XCTAssertEqual(Data(copying: owned), source)
    }

    func testDateBridgePreservesPreEpochFractionalInstants() throws {
        let source = try UnixInstant(
            secondsSinceUnixEpoch: -1,
            nanoseconds: 500_000_000
        )
        let roundTrip = try Date(source).networkingUnixInstant()
        XCTAssertEqual(roundTrip, source)
    }
}
