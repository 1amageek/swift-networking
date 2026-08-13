public enum TimeError: Error, Sendable, Equatable {
    case unavailable
    case cancelled
    case invalidNanoseconds(UInt32)
    case backendValueOutOfRange
    case arithmeticOverflow
    case movedBackwards
    case clockDomainMismatch(expected: UInt64, actual: UInt64)
    case backendFailure(code: Int)
}
