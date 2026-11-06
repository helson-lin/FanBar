import IOKit
import XCTest
@testable import FanBarHelper

final class SystemPowerObserverTests: XCTestCase {
    private final class Recorder {
        var events: [String] = []
        var acknowledged: [Int] = []
    }

    private func makeObserver(_ recorder: Recorder) -> SystemPowerObserver {
        SystemPowerObserver(
            willSleep: { recorder.events.append("willSleep") },
            didWake: { recorder.events.append("didWake") },
            allowPowerChange: { _, notificationID in
                recorder.events.append("allow")
                recorder.acknowledged.append(notificationID)
            }
        )
    }

    private func argument(_ notificationID: Int) -> UnsafeMutableRawPointer? {
        UnsafeMutableRawPointer(bitPattern: notificationID)
    }

    func testMessageTypesMapToTheIOKitConstants() {
        XCTAssertEqual(SystemPowerObserver.Message(messageType: 0xE000_0270), .canSleep)
        XCTAssertEqual(SystemPowerObserver.Message(messageType: 0xE000_0280), .willSleep)
        XCTAssertEqual(SystemPowerObserver.Message(messageType: 0xE000_0320), .wake)
        XCTAssertEqual(SystemPowerObserver.Message(messageType: 0xE000_0300), .wake)
        // kIOMessageSystemWillNotSleep: nothing was handed back, so nothing to undo.
        XCTAssertNil(SystemPowerObserver.Message(messageType: 0xE000_0290))
    }

    func testSleepIsAcknowledgedOnlyAfterTheFansAreHandedBack() {
        let recorder = Recorder()
        let observer = makeObserver(recorder)

        observer.handle(0xE000_0280, argument: argument(42))

        XCTAssertEqual(recorder.events, ["willSleep", "allow"])
        XCTAssertEqual(recorder.acknowledged, [42])
    }

    func testCanSleepIsAllowedWithoutHandingBack() {
        let recorder = Recorder()
        makeObserver(recorder).handle(0xE000_0270, argument: argument(7))

        XCTAssertEqual(recorder.events, ["allow"])
        XCTAssertEqual(recorder.acknowledged, [7])
    }

    func testWakeLiftsTheHoldWithoutAcknowledging() {
        let recorder = Recorder()
        let observer = makeObserver(recorder)

        observer.handle(0xE000_0320, argument: nil)
        observer.handle(0xE000_0300, argument: nil)
        observer.handle(0xE000_0290, argument: argument(3))

        XCTAssertEqual(recorder.events, ["didWake", "didWake"])
        XCTAssertTrue(recorder.acknowledged.isEmpty)
    }

    func testRegistersForSystemPowerAndReleasesIt() {
        let recorder = Recorder()
        var observer: SystemPowerObserver? = makeObserver(recorder)
        XCTAssertEqual(observer?.start(), true)
        observer = nil
        XCTAssertTrue(recorder.events.isEmpty, "Registering alone delivers no message")
    }
}
