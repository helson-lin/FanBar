import FanBarShared
import XCTest
@testable import FanBarHelper

final class SMCFanDriverTests: XCTestCase {
    private let fastUnlock = SMCFanDriver.UnlockTiming(settle: 0, deadline: 0.05, pollInterval: 0.005)

    /// Drivers restore automatic control in deinit, so keep each one alive
    /// until the test has inspected the SMC.
    private var liveDrivers: [SMCFanDriver] = []

    override func tearDown() {
        liveDrivers.removeAll()
        super.tearDown()
    }

    private func driver(_ smc: FakeSMC) -> SMCFanDriver {
        let driver = SMCFanDriver(store: smc, unlockTiming: fastUnlock)
        liveDrivers.append(driver)
        return driver
    }

    // MARK: Reading

    func testReadsFloat32FansAndPerFanManualFlag() throws {
        let smc = FakeSMC.appleSilicon()
        smc.set("F1md", bytes: [1])

        let fans = try driver(smc).fans()

        XCTAssertEqual(fans.map(\.index), [0, 1])
        XCTAssertEqual(fans.map(\.actual), [1_500, 1_600])
        XCTAssertEqual(fans.map(\.minimum), [1_200, 1_300])
        XCTAssertEqual(fans.map(\.maximum), [6_000, 6_500])
        XCTAssertEqual(fans.map(\.isManual), [false, true])
    }

    func testReadsFpe2FansAndForceMaskManualFlag() throws {
        let smc = FakeSMC.intelForceMask()
        smc.set(SMCFanDriver.forceMaskKey, bytes: [0, 0b10])

        let fans = try driver(smc).fans()

        XCTAssertEqual(fans.map(\.actual), [1_800, 1_700])
        XCTAssertEqual(fans.map(\.maximum), [5_500, 5_000])
        XCTAssertEqual(fans.map(\.isManual), [false, true])
    }

    func testRejectsImplausibleFanCount() {
        for count: UInt8 in [0, 9] {
            let smc = FakeSMC.appleSilicon()
            smc.set("FNum", bytes: [count])
            let driver = driver(smc)

            XCTAssertThrowsError(try driver.fans(), "FNum = \(count)") { error in
                guard case FanHardwareError.invalidValue("FNum") = error else {
                    return XCTFail("Unexpected error \(error)")
                }
            }
            XCTAssertThrowsError(try driver.restoreAutomatic(), "FNum = \(count)")
        }
    }

    // MARK: Writing within hardware limits

    func testSetAllFansClampsToEachFansHardwareRange() throws {
        let smc = FakeSMC.appleSilicon()
        let driver = driver(smc)

        try driver.setAllFans(rpm: 99_999)
        XCTAssertEqual(smc.rpm("F0Tg"), 6_000)
        XCTAssertEqual(smc.rpm("F1Tg"), 6_500)
        XCTAssertEqual(smc.bytes("F0md"), [1])
        XCTAssertEqual(smc.bytes("F1md"), [1])

        try driver.setAllFans(rpm: 10)
        XCTAssertEqual(smc.rpm("F0Tg"), 1_200)
        XCTAssertEqual(smc.rpm("F1Tg"), 1_300)
    }

    func testPresetUsesSharedCoolingTargetRule() throws {
        let smc = FakeSMC.appleSilicon()

        try driver(smc).setCoolingPreset(.balanced)

        XCTAssertEqual(smc.rpm("F0Tg"), FanCoolingTarget.targetRPM(fraction: 0.5, minimum: 1_200, maximum: 6_000))
        XCTAssertEqual(smc.rpm("F1Tg"), FanCoolingTarget.targetRPM(fraction: 0.5, minimum: 1_300, maximum: 6_500))
    }

    func testEightyPercentIsTheExtremePreset() throws {
        let smc = FakeSMC.appleSilicon()

        try driver(smc).setAllFansToEightyPercent()

        XCTAssertEqual(FanCoolingPreset.extreme.maximumFraction, 0.8)
        XCTAssertEqual(smc.rpm("F0Tg"), 4_800)
    }

    func testZeroFractionIsAnExplicitManualIdle() throws {
        let smc = FakeSMC.appleSilicon()

        try driver(smc).setCoolingFraction(0)

        XCTAssertEqual(smc.bytes("F0md"), [1])
        XCTAssertEqual(smc.rpm("F0Tg"), 0)
    }

    func testOutOfRangeFractionsNeverTouchHardware() {
        let smc = FakeSMC.appleSilicon()
        let driver = driver(smc)

        for fraction: Float in [.nan, .infinity, -0.01, 1.01] {
            XCTAssertThrowsError(try driver.setCoolingFraction(fraction), "\(fraction)")
        }
        XCTAssertEqual(smc.writtenKeys, [])
    }

    func testFpe2TargetEncoding() throws {
        let smc = FakeSMC.intelForceMask()

        try driver(smc).setAllFans(rpm: 1_500)

        // 1500 RPM * 4 = 6000 = 0x1770.
        XCTAssertEqual(smc.bytes("F0Tg"), [0x17, 0x70])
    }

    // MARK: Manual mode

    func testUppercaseModeKeyIsDetected() throws {
        let smc = FakeSMC.appleSilicon(modeKeyFormat: "F%dMd")

        try driver(smc).setAllFans(rpm: 3_000)

        XCTAssertEqual(smc.bytes("F0Md"), [1])
        XCTAssertEqual(smc.bytes("F1Md"), [1])
    }

    func testForceMaskSetsAndClearsOneBitPerFan() throws {
        let smc = FakeSMC.intelForceMask()
        let driver = driver(smc)

        try driver.setAllFans(rpm: 3_000)
        XCTAssertEqual(smc.forceMask, 0b11)

        try driver.restoreAutomatic()
        XCTAssertEqual(smc.forceMask, 0)
        XCTAssertEqual(smc.rpm("F0Tg"), 0)
        XCTAssertEqual(smc.rpm("F1Tg"), 0)
    }

    func testForceTestUnlocksManualModeAndIsClearedOnRestore() throws {
        let smc = FakeSMC.appleSilicon()
        smc.manualModeRequiresForceTest = true
        let driver = driver(smc)

        try driver.setAllFans(rpm: 3_000)
        XCTAssertEqual(smc.bytes("Ftst"), [1])
        XCTAssertEqual(smc.bytes("F0md"), [1])
        XCTAssertEqual(smc.rpm("F0Tg"), 3_000)

        try driver.restoreAutomatic()
        XCTAssertEqual(smc.bytes("Ftst"), [0])
        XCTAssertEqual(smc.bytes("F0md"), [0])
    }

    func testUnlockTimeoutRollsBackToAutomatic() {
        let smc = FakeSMC.appleSilicon()
        smc.rejectsManualMode = true

        XCTAssertThrowsError(try driver(smc).setAllFans(rpm: 3_000)) { error in
            guard case FanHardwareError.unlockTimeout(0) = error else {
                return XCTFail("Unexpected error \(error)")
            }
        }
        XCTAssertEqual(smc.bytes("Ftst"), [0])
        XCTAssertEqual(smc.rpm("F0Tg"), 0)
    }

    func testRejectedModeWriteWithoutForceTestFails() {
        let smc = FakeSMC.appleSilicon(forceTest: false)
        smc.rejectsManualMode = true

        XCTAssertThrowsError(try driver(smc).setAllFans(rpm: 3_000)) { error in
            guard case FanHardwareError.operation("F0md", -1) = error else {
                return XCTFail("Unexpected error \(error)")
            }
        }
    }

    func testMissingModeKeyRefusesManualControl() throws {
        let smc = FakeSMC.withoutModeKey()
        let driver = driver(smc)

        XCTAssertEqual(try driver.fans().map(\.isManual), [false])
        XCTAssertThrowsError(try driver.setAllFans(rpm: 3_000)) { error in
            guard case FanHardwareError.modeKeyMissing = error else {
                return XCTFail("Unexpected error \(error)")
            }
        }
        XCTAssertEqual(smc.rpm("F0Tg"), 0)
    }

    // MARK: Falling back to macOS

    func testPartialMultiFanWriteRollsEveryFanBack() {
        let smc = FakeSMC.appleSilicon()
        smc.failWrites(to: "F1Tg", code: -5)

        XCTAssertThrowsError(try driver(smc).setCoolingFraction(0.5)) { error in
            guard case FanHardwareError.operation("F1Tg", -5) = error else {
                return XCTFail("Unexpected error \(error)")
            }
        }
        // Fan 0 was already switched before fan 1 failed.
        XCTAssertEqual(smc.bytes("F0md"), [0])
        XCTAssertEqual(smc.rpm("F0Tg"), 0)
        XCTAssertEqual(smc.bytes("F1md"), [0])
    }

    func testRestoreKeepsGoingAfterAFailureAndReportsTheFirst() {
        let smc = FakeSMC.appleSilicon()
        smc.set("F0md", bytes: [1])
        smc.set("F1md", bytes: [1])
        smc.set("F1Tg", rpm: 4_000)
        smc.set("Ftst", bytes: [1])
        smc.failWrites(to: "F0md", code: -7)

        XCTAssertThrowsError(try driver(smc).restoreAutomatic()) { error in
            guard case FanHardwareError.operation("F0md", -7) = error else {
                return XCTFail("Unexpected error \(error)")
            }
        }
        XCTAssertEqual(smc.bytes("F1md"), [0])
        XCTAssertEqual(smc.rpm("F1Tg"), 0)
        XCTAssertEqual(smc.bytes("Ftst"), [0])
    }

    func testReleasingTheDriverRestoresAutomatic() throws {
        let smc = FakeSMC.appleSilicon()
        do {
            let driver = SMCFanDriver(store: smc, unlockTiming: fastUnlock)
            try driver.setAllFans(rpm: 3_000)
            XCTAssertEqual(smc.bytes("F0md"), [1])
        }
        XCTAssertEqual(smc.bytes("F0md"), [0])
        XCTAssertEqual(smc.bytes("F1md"), [0])
        XCTAssertEqual(smc.rpm("F0Tg"), 0)
    }

    // MARK: Probing again after a slow SMC

    /// An SMC that answers slowly right after wake, not a missing key.
    private let timedOut = Int32(bitPattern: 0xE000_02D6)

    func testFailedModeKeyProbeIsRetriedInsteadOfReportedMissing() throws {
        let smc = FakeSMC.appleSilicon()
        smc.failReads(of: "F0md", code: timedOut)
        smc.failReads(of: "F0Md", code: timedOut)
        smc.failReads(of: SMCFanDriver.forceMaskKey, code: timedOut)
        let driver = driver(smc)

        XCTAssertThrowsError(try driver.setAllFans(rpm: 3_000)) { error in
            guard case FanHardwareError.operation(_, timedOut) = error else {
                return XCTFail("A slow answer was reported as \(error)")
            }
        }

        smc.failReads(of: "F0md", code: nil)
        smc.failReads(of: "F0Md", code: nil)
        smc.failReads(of: SMCFanDriver.forceMaskKey, code: nil)
        try driver.setAllFans(rpm: 3_000)
        XCTAssertEqual(smc.bytes("F0md"), [1])
        XCTAssertEqual(smc.rpm("F0Tg"), 3_000)
    }

    func testFailedForceTestProbeIsRetriedOnTheNextWrite() throws {
        let smc = FakeSMC.appleSilicon()
        smc.manualModeRequiresForceTest = true
        smc.failReads(of: "Ftst", code: timedOut)
        let driver = driver(smc)

        XCTAssertThrowsError(try driver.setAllFans(rpm: 3_000))

        smc.failReads(of: "Ftst", code: nil)
        try driver.setAllFans(rpm: 3_000)
        XCTAssertEqual(smc.bytes("Ftst"), [1])
        XCTAssertEqual(smc.bytes("F0md"), [1])
    }

    func testRestoreStillClearsTargetsWhenTheModeProbeFails() throws {
        let smc = FakeSMC.appleSilicon()
        smc.set("F0Tg", rpm: 4_000)
        smc.set("Ftst", bytes: [1])
        smc.failReads(of: "F0md", code: timedOut)
        smc.failReads(of: "F0Md", code: timedOut)
        smc.failReads(of: SMCFanDriver.forceMaskKey, code: timedOut)
        let driver = driver(smc)

        XCTAssertThrowsError(try driver.restoreAutomatic())
        XCTAssertEqual(smc.rpm("F0Tg"), 0)
        XCTAssertEqual(smc.bytes("Ftst"), [0])
    }

    func testRestoreClearsEveryCandidateModeKeyWhenTheProbeFails() {
        let smc = FakeSMC.appleSilicon()
        smc.set("F0md", bytes: [1])
        smc.set("F1md", bytes: [1])
        smc.set("F0Tg", rpm: 4_000)
        smc.set("Ftst", bytes: [1])
        // One failure for the probe when the driver opens, one for the probe in restore.
        smc.failNextReads(of: "F0md", count: 2, code: timedOut)
        let driver = driver(smc)

        XCTAssertThrowsError(try driver.restoreAutomatic()) { error in
            guard case FanHardwareError.operation("F0md", timedOut) = error else {
                return XCTFail("Reported \(error) instead of the failed probe")
            }
        }
        XCTAssertEqual(smc.bytes("F0md"), [0], "Fan 0 was left in manual mode")
        XCTAssertEqual(smc.bytes("F1md"), [0], "Fan 1 was left in manual mode")
        XCTAssertEqual(smc.rpm("F0Tg"), 0)
        XCTAssertEqual(smc.bytes("Ftst"), [0])
    }

    func testReadingFansReportsAFailedModeProbeInsteadOfAutomatic() {
        let smc = FakeSMC.appleSilicon()
        smc.set("F0md", bytes: [1])
        smc.failReads(of: "F0md", code: timedOut)
        smc.failReads(of: "F0Md", code: timedOut)
        smc.failReads(of: SMCFanDriver.forceMaskKey, code: timedOut)

        XCTAssertThrowsError(try driver(smc).fans())
    }

    // MARK: Reopening a dropped connection

    func testDroppedConnectionIsReopenedAndTheCallRepeatedOnce() {
        var results: [Int32] = [Int32(bitPattern: 0xE000_02CD), 0]
        var reopened = 0
        let result = AppleSMCKeyStore.reconnecting {
            results.removeFirst()
        } reopen: {
            reopened += 1
            return 0
        }

        XCTAssertEqual(result, 0)
        XCTAssertEqual(reopened, 1)
        XCTAssertTrue(results.isEmpty)
    }

    func testSMCRefusalIsNotMistakenForADroppedConnection() {
        var calls = 0
        var reopened = 0
        let refused = FanHardwareError.keyNotFoundCode
        let result = AppleSMCKeyStore.reconnecting {
            calls += 1
            return refused
        } reopen: {
            reopened += 1
            return 0
        }

        XCTAssertEqual(result, refused)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(reopened, 0)
    }

    func testFailedReopenReportsTheOriginalFailure() {
        let lost = Int32(bitPattern: 0x1000_0003)
        var calls = 0
        let result = AppleSMCKeyStore.reconnecting {
            calls += 1
            return lost
        } reopen: {
            Int32(bitPattern: 0xE000_02C0)
        }

        XCTAssertEqual(result, lost)
        XCTAssertEqual(calls, 1)
    }

    func testConnectionLostCodes() {
        XCTAssertTrue(AppleSMCKeyStore.isConnectionLost(Int32(bitPattern: 0x1000_0003)))
        XCTAssertTrue(AppleSMCKeyStore.isConnectionLost(-308))
        XCTAssertFalse(AppleSMCKeyStore.isConnectionLost(0))
        XCTAssertFalse(AppleSMCKeyStore.isConnectionLost(FanHardwareError.keyNotFoundCode))
        XCTAssertFalse(AppleSMCKeyStore.isConnectionLost(timedOut))
    }
}
