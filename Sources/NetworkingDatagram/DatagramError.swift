public enum DatagramError: Error, Sendable, Equatable {
    case closed
    case cancelled
    case concurrentReceive
    case invalidBufferCapacity(Int)
    case messageTooLarge(size: Int, maximum: Int)
    case invalidEndpoint
    case networkInterfaceNotFound(String)
    case receiveQueueOverflow(capacity: Int)
    case unsupportedCapability(DatagramTransportCapabilities)
    case backendFailure(operation: DatagramOperation, code: Int, terminal: Bool)
}
