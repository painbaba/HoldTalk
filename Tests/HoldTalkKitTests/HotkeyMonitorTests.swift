import ApplicationServices
import XCTest
@testable import HoldTalkKit

/// Feeds handmade key events straight into the handler. Nothing is posted to the
/// system, so these tests can't press keys in another app.
@MainActor
final class HotkeyMonitorTests: XCTestCase {
    private var signals: [HotkeyMonitor.Signal] = []

    private func makeMonitor(_ hotkey: Hotkey) -> HotkeyMonitor {
        signals = []
        let monitor = HotkeyMonitor()
        monitor.prepare(hotkey: hotkey)
        monitor.onSignal = { [weak self] in self?.signals.append($0) }
        return monitor
    }

    private func flagsChanged(code: CGKeyCode, flags: UInt64) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)!
        event.type = .flagsChanged
        event.setIntegerValueField(.keyboardEventKeycode, value: Int64(code))
        event.flags = CGEventFlags(rawValue: flags)
        return event
    }

    private func keyDown(code: CGKeyCode, autorepeat: Bool = false) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)!
        event.setIntegerValueField(.keyboardEventAutorepeat, value: autorepeat ? 1 : 0)
        return event
    }

    func testFnPressAndRelease() {
        let monitor = makeMonitor(.modifier(.fn))
        monitor.handle(type: .flagsChanged, event: flagsChanged(code: 63, flags: CGEventFlags.maskSecondaryFn.rawValue))
        monitor.handle(type: .flagsChanged, event: flagsChanged(code: 63, flags: 0))
        XCTAssertEqual(signals, [.hotkeyDown, .hotkeyUp])
    }

    func testGlobeKeyCode() {
        let monitor = makeMonitor(.modifier(.fn))
        monitor.handle(type: .flagsChanged, event: flagsChanged(code: 179, flags: CGEventFlags.maskSecondaryFn.rawValue))
        XCTAssertEqual(signals, [.hotkeyDown])
    }

    func testRightOptionIgnoresLeftOption() {
        let monitor = makeMonitor(.modifier(.rightOption))
        let optionFlag = CGEventFlags.maskAlternate.rawValue
        monitor.handle(type: .flagsChanged, event: flagsChanged(code: 58, flags: optionFlag | 0x20))
        XCTAssertEqual(signals, [], "Left option isn't the hotkey")
        monitor.handle(type: .flagsChanged, event: flagsChanged(code: 58, flags: 0))

        monitor.handle(type: .flagsChanged, event: flagsChanged(code: 61, flags: optionFlag | 0x40))
        XCTAssertEqual(signals, [.hotkeyDown])
        monitor.handle(type: .flagsChanged, event: flagsChanged(code: 61, flags: 0))
        XCTAssertEqual(signals, [.hotkeyDown, .hotkeyUp])
    }

    func testRightOptionReleasedWhileLeftStaysDown() {
        let monitor = makeMonitor(.modifier(.rightOption))
        let optionFlag = CGEventFlags.maskAlternate.rawValue
        monitor.handle(type: .flagsChanged, event: flagsChanged(code: 61, flags: optionFlag | 0x60))
        monitor.handle(type: .flagsChanged, event: flagsChanged(code: 61, flags: optionFlag | 0x20))
        XCTAssertEqual(signals, [.hotkeyDown, .hotkeyUp], "The combined option flag alone would miss this")
    }

    func testRepeatedFlagEventsDoNotRepeatSignals() {
        let monitor = makeMonitor(.modifier(.fn))
        let down = flagsChanged(code: 63, flags: CGEventFlags.maskSecondaryFn.rawValue)
        monitor.handle(type: .flagsChanged, event: down)
        monitor.handle(type: .flagsChanged, event: down)
        XCTAssertEqual(signals, [.hotkeyDown])
    }

    func testEscapeSeenWithOrWithoutHotkey() {
        let monitor = makeMonitor(.modifier(.fn))
        monitor.handle(type: .keyDown, event: keyDown(code: 53))
        XCTAssertEqual(signals, [.escape])
    }

    func testOtherKeysOnlyMatterWhileHotkeyIsDown() {
        let monitor = makeMonitor(.modifier(.fn))
        monitor.handle(type: .keyDown, event: keyDown(code: 0))
        XCTAssertEqual(signals, [], "Normal typing is ignored")

        monitor.handle(type: .flagsChanged, event: flagsChanged(code: 63, flags: CGEventFlags.maskSecondaryFn.rawValue))
        monitor.handle(type: .keyDown, event: keyDown(code: 123, autorepeat: true))
        XCTAssertEqual(signals, [.hotkeyDown], "Key repeat doesn't count")
        monitor.handle(type: .keyDown, event: keyDown(code: 123))
        XCTAssertEqual(signals, [.hotkeyDown, .otherKey])
    }

    func testOtherModifierWhileHotkeyIsDownIsAChord() {
        let monitor = makeMonitor(.modifier(.fn))
        let fnFlag = CGEventFlags.maskSecondaryFn.rawValue
        monitor.handle(type: .flagsChanged, event: flagsChanged(code: 63, flags: fnFlag))
        monitor.handle(type: .flagsChanged, event: flagsChanged(code: 59, flags: fnFlag | CGEventFlags.maskControl.rawValue))
        XCTAssertEqual(signals, [.hotkeyDown, .otherKey])
    }

    func testComboHotkeyLeavesModifierEventsAlone() {
        let monitor = makeMonitor(.combo(keyCode: 49, modifiers: [.control, .option]))
        monitor.handle(type: .flagsChanged, event: flagsChanged(code: 63, flags: CGEventFlags.maskSecondaryFn.rawValue))
        monitor.handle(type: .keyDown, event: keyDown(code: 0))
        XCTAssertEqual(signals, [])
        monitor.handle(type: .keyDown, event: keyDown(code: 53))
        XCTAssertEqual(signals, [.escape], "Esc still cancels")
    }

    func testPasteKeyIsFound() {
        let code = TextInserter.keyCodeForV()
        XCTAssertLessThan(code, 128)
    }
}
