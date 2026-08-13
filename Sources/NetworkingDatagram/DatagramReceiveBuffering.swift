public struct DatagramReceiveBuffering: Sendable, Hashable {
    public let capacity: Int
    public let overflowPolicy: DatagramOverflowPolicy

    public init(
        capacity: Int,
        overflowPolicy: DatagramOverflowPolicy
    ) throws(DatagramError) {
        guard capacity > 0 else {
            throw .invalidBufferCapacity(capacity)
        }
        self.capacity = capacity
        self.overflowPolicy = overflowPolicy
    }
}
