import XCTest
import NetworkingTime

final class NetworkingTimeTests: XCTestCase {
    func testContinuousTimerFirstReadUsesInitializedOrigin() throws {
        let first = try ContinuousAsyncTimer().now()
        let second = try ContinuousAsyncTimer().now()

        XCTAssertEqual(first.clockIdentifier, second.clockIdentifier)
        XCTAssertGreaterThanOrEqual(second.nanoseconds, first.nanoseconds)
    }

    func testContinuousTimerCancellationReturnsBeforeDeadline() async throws {
        let timer = ContinuousAsyncTimer()
        let deadline = try timer.now().advanced(byNanoseconds: 5_000_000_000)
        let task = Task {
            try await timer.sleep(until: deadline)
        }
        await Task.yield()
        task.cancel()

        do {
            try await task.value
            XCTFail("Cancelled timer unexpectedly reached its deadline")
        } catch let error as TimeError {
            XCTAssertEqual(error, .cancelled)
        }
    }

    func testUnixNanosecondsAreCanonical() {
        XCTAssertThrowsError(
            try UnixInstant(
                secondsSinceUnixEpoch: 0,
                nanoseconds: 1_000_000_000
            )
        ) { error in
            XCTAssertEqual(error as? TimeError, .invalidNanoseconds(1_000_000_000))
        }
    }

    func testMonotonicDomainsCannotBeMixed() {
        let first = MonotonicInstant(clockIdentifier: 1, nanoseconds: 10)
        let second = MonotonicInstant(clockIdentifier: 2, nanoseconds: 20)
        XCTAssertThrowsError(try second.durationNanoseconds(since: first)) { error in
            XCTAssertEqual(
                error as? TimeError,
                .clockDomainMismatch(expected: 2, actual: 1)
            )
        }
    }

    func testMonotonicDurationUsesNanosecondsWithinOneDomain() throws {
        let earlier = MonotonicInstant(clockIdentifier: 1, nanoseconds: 10)
        let later = MonotonicInstant(clockIdentifier: 1, nanoseconds: 25)

        XCTAssertEqual(try later.durationNanoseconds(since: earlier), 15)
    }

    func testMonotonicDurationRejectsClockRegression() {
        let earlier = MonotonicInstant(clockIdentifier: 1, nanoseconds: 20)
        let later = MonotonicInstant(clockIdentifier: 1, nanoseconds: 10)

        XCTAssertThrowsError(try later.durationNanoseconds(since: earlier)) { error in
            XCTAssertEqual(error as? TimeError, .movedBackwards)
        }
    }
}
