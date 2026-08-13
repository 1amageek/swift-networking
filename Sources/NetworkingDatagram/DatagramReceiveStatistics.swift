public struct DatagramReceiveStatistics: Sendable, Hashable {
    public let receivedDatagramCount: UInt64
    public let droppedDatagramCount: UInt64

    public init(receivedDatagramCount: UInt64, droppedDatagramCount: UInt64) {
        self.receivedDatagramCount = receivedDatagramCount
        self.droppedDatagramCount = droppedDatagramCount
    }
}
