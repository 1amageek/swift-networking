import XCTest
import NetworkingCore
import NetworkingDatagram

final class NetworkingDatagramTests: XCTestCase {
    func testReceiveBuffersRequirePositiveCapacity() {
        XCTAssertThrowsError(
            try DatagramReceiveBuffering(
                capacity: 0,
                overflowPolicy: .failTransport
            )
        ) { error in
            XCTAssertEqual(error as? DatagramError, .invalidBufferCapacity(0))
        }
    }

    func testOutboundMetadataDeclaresRequiredCapabilities() throws {
        let interface = try NetworkInterfaceIndex(rawValue: 4)
        let metadata = DatagramSendMetadata(
            sourceAddress: .v4(10, 0, 0, 1),
            interfaceIndex: interface,
            explicitCongestionNotification: .ect0
        )
        XCTAssertTrue(metadata.requiredCapabilities.contains(.sourceAddressSelection))
        XCTAssertTrue(metadata.requiredCapabilities.contains(.interfaceIndex))
        XCTAssertTrue(
            metadata.requiredCapabilities.contains(.explicitCongestionNotification)
        )
    }
}
