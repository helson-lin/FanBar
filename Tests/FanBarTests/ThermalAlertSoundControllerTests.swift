import AppKit
import FanBarShared
import SwiftUI
import XCTest
@testable import FanBar

@MainActor
final class ThermalAlertSoundControllerTests: XCTestCase {
    private let keys = [ThermalAlertSettings.soundKey, FanBarLanguage.preferenceKey]
    // XCTest lifecycle overrides are nonisolated even though this UI test case runs
    // on the main actor. XCTest invokes them serially around each test.
    private nonisolated(unsafe) var saved: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        for key in keys {
            saved[key] = UserDefaults.standard.object(forKey: key)
        }
        UserDefaults.standard.removeObject(forKey: ThermalAlertSettings.soundKey)
    }

    override func tearDown() {
        for key in keys {
            if let value = saved[key] {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        super.tearDown()
    }

    private func makeController() -> FanController {
        let source = FakeFanReadingSource(readings: [
            FanReading(index: 0, minimumRPM: 1200, currentRPM: 1850, maximumRPM: 6000, isManual: false),
        ])
        return FanController(
            notificationCenter: nil, widgetSnapshotDestination: .disabled, makeReadingSource: { source }
        )
    }

    func testChoosingASoundPersistsIt() {
        let controller = makeController()
        XCTAssertEqual(controller.highTemperatureAlertSound, .notificationDefault)

        controller.setHighTemperatureAlertSound(.silent)
        XCTAssertEqual(controller.highTemperatureAlertSound, .silent)
        XCTAssertEqual(UserDefaults.standard.string(forKey: ThermalAlertSettings.soundKey), "none")

        controller.setHighTemperatureAlertSound(.system("Tink"))
        XCTAssertEqual(UserDefaults.standard.string(forKey: ThermalAlertSettings.soundKey), "Tink")
        XCTAssertEqual(makeController().highTemperatureAlertSound, .system("Tink"))

        // The default is stored as no value so it follows future releases.
        controller.setHighTemperatureAlertSound(.notificationDefault)
        XCTAssertNil(UserDefaults.standard.object(forKey: ThermalAlertSettings.soundKey))
        controller.previewHighTemperatureAlertSound()
        XCTAssertEqual(controller.highTemperatureAlertSound, .notificationDefault)
    }

    func testPlayerReportsSoundsItCannotLoad() {
        XCTAssertFalse(ThermalAlertSoundPlayer.play("NotARealSound"))
        // A second call stops the previous sound first; playback itself
        // depends on the host's audio device, so only loading is asserted.
        ThermalAlertSoundPlayer.play("Tink")
        ThermalAlertSoundPlayer.play("Tink")
        XCTAssertFalse(ThermalAlertSoundPlayer.play("NotARealSound"))
    }

    func testTitlesFollowTheInterfaceLanguage() {
        UserDefaults.standard.set(FanBarLanguage.english.rawValue, forKey: FanBarLanguage.preferenceKey)
        XCTAssertEqual(ThermalAlertSound.notificationDefault.title, "Notification default")
        XCTAssertEqual(ThermalAlertSound.silent.title, "None")
        XCTAssertEqual(ThermalAlertSound.system("Glass").title, "Glass")
        UserDefaults.standard.set(FanBarLanguage.chinese.rawValue, forKey: FanBarLanguage.preferenceKey)
        XCTAssertEqual(ThermalAlertSound.notificationDefault.title, "通知默认")
        XCTAssertEqual(ThermalAlertSound.silent.title, "无")
    }

    func testSoundRowLaysOutForEverySelection() {
        let controller = makeController()
        for sound in [ThermalAlertSound.notificationDefault, .silent, .system("Glass")] {
            controller.setHighTemperatureAlertSound(sound)
            // Roughly the settings card's content width: the detail wraps
            // instead of pushing the picker out of the row.
            let host = NSHostingView(rootView: ThermalAlertSoundRow(controller: controller).frame(width: 480))
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(host.fittingSize.width, 480, accuracy: 0.5)
            XCTAssertGreaterThan(host.fittingSize.height, 20)
            XCTAssertLessThan(host.fittingSize.height, 120)
        }
    }
}
