public enum TLSVocabularyError: Error, Sendable, Equatable {
    case invalidLength(actual: Int)
}
