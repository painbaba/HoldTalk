import XCTest
@testable import HoldTalkKit

final class DictationMachineTests: XCTestCase {
    private var machine = DictationMachine(tapMaxSeconds: 0.25, doubleTapWindowSeconds: 0.35)

    override func setUp() {
        machine = DictationMachine(tapMaxSeconds: 0.25, doubleTapWindowSeconds: 0.35)
    }

    func testLongHoldRecordsThenTranscribesOnRelease() {
        XCTAssertEqual(machine.handle(.hotkeyDown(at: 10)), [.startRecording])
        XCTAssertEqual(machine.state, .holding(since: 10))
        XCTAssertEqual(machine.handle(.hotkeyUp(at: 12)), [.finishRecording])
        XCTAssertEqual(machine.state, .processing)
        XCTAssertEqual(machine.handle(.processingFinished), [])
        XCTAssertEqual(machine.state, .idle)
    }

    func testSingleQuickTapIsThrownAway() {
        _ = machine.handle(.hotkeyDown(at: 10))
        XCTAssertEqual(machine.handle(.hotkeyUp(at: 10.1)), [.startSecondTapTimer(0.35)])
        XCTAssertTrue(machine.isRecording)
        XCTAssertEqual(machine.handle(.secondTapTimedOut), [.discardRecording])
        XCTAssertEqual(machine.state, .idle)
    }

    func testDoubleTapStartsHandsFreeAndOneMoreTapStops() {
        _ = machine.handle(.hotkeyDown(at: 10))
        _ = machine.handle(.hotkeyUp(at: 10.1))
        XCTAssertEqual(machine.handle(.hotkeyDown(at: 10.2)), [.cancelSecondTapTimer])
        XCTAssertEqual(machine.state, .handsFree)

        XCTAssertEqual(machine.handle(.hotkeyUp(at: 10.3)), [], "Releasing the second tap must not stop it")
        XCTAssertEqual(machine.state, .handsFree)

        XCTAssertEqual(machine.handle(.hotkeyDown(at: 40)), [.finishRecording])
        XCTAssertEqual(machine.state, .processing)
        XCTAssertEqual(machine.handle(.hotkeyUp(at: 40.1)), [], "Releasing the stop tap does nothing")
    }

    func testHandsFreeAutoStopsAtLimitAndTranscribes() {
        _ = machine.handle(.hotkeyDown(at: 10))
        _ = machine.handle(.hotkeyUp(at: 10.1))
        _ = machine.handle(.hotkeyDown(at: 10.2))
        XCTAssertEqual(machine.handle(.recordingLimitReached), [.finishRecording])
        XCTAssertEqual(machine.state, .processing)
    }

    func testStuckHoldAlsoStopsAtLimit() {
        _ = machine.handle(.hotkeyDown(at: 10))
        XCTAssertEqual(machine.handle(.recordingLimitReached), [.finishRecording])
        XCTAssertEqual(machine.handle(.hotkeyUp(at: 400)), [], "A late release does nothing")
        XCTAssertEqual(machine.state, .processing)
    }

    func testEscapeDropsRecordingInEveryRecordingState() {
        _ = machine.handle(.hotkeyDown(at: 10))
        XCTAssertEqual(machine.handle(.escape), [.discardRecording])
        XCTAssertEqual(machine.state, .idle)
        XCTAssertEqual(machine.handle(.hotkeyUp(at: 11)), [], "Release after Esc does nothing")

        _ = machine.handle(.hotkeyDown(at: 20))
        _ = machine.handle(.hotkeyUp(at: 20.1))
        XCTAssertEqual(machine.handle(.escape), [.cancelSecondTapTimer, .discardRecording])
        XCTAssertEqual(machine.state, .idle)

        _ = machine.handle(.hotkeyDown(at: 30))
        _ = machine.handle(.hotkeyUp(at: 30.1))
        _ = machine.handle(.hotkeyDown(at: 30.2))
        XCTAssertEqual(machine.handle(.escape), [.discardRecording])
        XCTAssertEqual(machine.state, .idle)
    }

    func testEscapeKillsRunningTranscription() {
        _ = machine.handle(.hotkeyDown(at: 10))
        _ = machine.handle(.hotkeyUp(at: 12))
        XCTAssertEqual(machine.handle(.escape), [.cancelProcessing])
        XCTAssertEqual(machine.state, .idle)
    }

    func testEscapeWhileIdleDoesNothing() {
        XCTAssertEqual(machine.handle(.escape), [])
        XCTAssertEqual(machine.state, .idle)
    }

    func testPressWhileTranscribingIsIgnored() {
        _ = machine.handle(.hotkeyDown(at: 10))
        _ = machine.handle(.hotkeyUp(at: 12))
        XCTAssertEqual(machine.handle(.hotkeyDown(at: 13)), [])
        XCTAssertEqual(machine.handle(.hotkeyUp(at: 14)), [])
        XCTAssertEqual(machine.state, .processing)
    }

    func testLateTimerCannotDropHandsFree() {
        _ = machine.handle(.hotkeyDown(at: 10))
        _ = machine.handle(.hotkeyUp(at: 10.1))
        _ = machine.handle(.hotkeyDown(at: 10.2))
        XCTAssertEqual(machine.handle(.secondTapTimedOut), [])
        XCTAssertEqual(machine.state, .handsFree)
    }

    func testChordSoonAfterPressCancels() {
        _ = machine.handle(.hotkeyDown(at: 10))
        XCTAssertEqual(machine.handle(.otherKey(at: 10.4)), [.discardRecording])
        XCTAssertEqual(machine.state, .idle)
    }

    func testKeyLongAfterPressKeepsRecording() {
        _ = machine.handle(.hotkeyDown(at: 10))
        XCTAssertEqual(machine.handle(.otherKey(at: 13)), [])
        XCTAssertEqual(machine.state, .holding(since: 10))
    }

    func testMicFailureReturnsToIdle() {
        _ = machine.handle(.hotkeyDown(at: 10))
        XCTAssertEqual(machine.handle(.recordingFailed), [.discardRecording])
        XCTAssertEqual(machine.state, .idle)
    }

    func testShutDownStopsEverything() {
        _ = machine.handle(.hotkeyDown(at: 10))
        XCTAssertEqual(machine.handle(.shutDown), [.discardRecording])
        _ = machine.handle(.hotkeyDown(at: 20))
        _ = machine.handle(.hotkeyUp(at: 22))
        XCTAssertEqual(machine.handle(.shutDown), [.cancelProcessing])
        XCTAssertEqual(machine.state, .idle)
    }
}
