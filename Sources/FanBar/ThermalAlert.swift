import AppKit
import FanBarShared
import UserNotifications

enum ThermalAlertSettings {
    static let notificationsEnabledKey = "fanbar.highTemperatureNotificationsEnabled"
    static let thresholdKey = "fanbar.highTemperatureThresholdCelsius"
    static let defaultThresholdCelsius = 90.0
    /// Below 60°C alerts would fire during ordinary load; above 105°C Apple
    /// silicon is already throttling, so a warning would arrive too late.
    static let thresholdRange: ClosedRange<Double> = 60...105

    /// The user's alert threshold, falling back to the default when unset.
    static var thresholdCelsius: Double {
        let stored = UserDefaults.standard.object(forKey: thresholdKey) as? Double
        return clampedThreshold(stored ?? defaultThresholdCelsius)
    }

    static func clampedThreshold(_ celsius: Double) -> Double {
        min(max(celsius.rounded(), thresholdRange.lowerBound), thresholdRange.upperBound)
    }

    static let notificationIdentifierPrefix = "fanbar.high-temperature"

    static let soundKey = "fanbar.highTemperatureAlertSound"

    /// The user's alert sound. Unset keeps the notification's default sound,
    /// which is what alerts played before the sound became a setting.
    static var sound: ThermalAlertSound {
        ThermalAlertSound(storedValue: UserDefaults.standard.string(forKey: soundKey))
    }

    /// Two warnings within this window share one sound. The episode monitor
    /// already alerts once per episode, but a temperature hovering at the
    /// threshold, or dragging the threshold across it, starts a new episode
    /// every few seconds.
    static let soundCooldown: TimeInterval = 120
}

/// What a high-temperature alert sounds like.
enum ThermalAlertSound: Hashable {
    /// The notification's own sound, which macOS mutes when FanBar's
    /// notification sounds are off or a Focus is on.
    case notificationDefault
    case silent
    /// A named system alert sound, played by FanBar itself so it is heard
    /// even when notification sounds are muted.
    case system(String)

    /// The alert sounds every macOS release since 11 ships in /System/Library/Sounds.
    static let systemSoundNames = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
        "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink",
    ]

    private static let silentValue = "none"

    /// Unknown names, such as a sound a later macOS dropped, fall back to the default.
    init(storedValue: String?) {
        switch storedValue {
        case Self.silentValue: self = .silent
        case let name? where Self.systemSoundNames.contains(name): self = .system(name)
        default: self = .notificationDefault
        }
    }

    /// Nil removes the stored value so the default follows future releases.
    var storedValue: String? {
        switch self {
        case .notificationDefault: nil
        case .silent: Self.silentValue
        case let .system(name): name
        }
    }

    var title: String {
        switch self {
        case .notificationDefault: fanBarText("通知默认", "Notification default")
        case .silent: fanBarText("无", "None")
        case let .system(name): name
        }
    }

    /// The sound FanBar plays itself; nil when the notification carries it or there is none.
    var systemSoundName: String? {
        if case let .system(name) = self { return name }
        return nil
    }

    /// Plays a system sound through `play` and returns the sound the
    /// notification carries: none when FanBar played it, so it is not heard
    /// twice. A system sound that fails to load falls back to the default
    /// notification sound, so a missing file never silences an alert.
    func deliver(playing play: (String) -> Bool) -> UNNotificationSound? {
        switch self {
        case .notificationDefault: .default
        case .silent: nil
        case let .system(name): play(name) ? nil : .default
        }
    }
}

/// Lets an alert sound once per cooldown window, however many episodes start in it.
struct ThermalAlertSoundGate {
    var cooldown: TimeInterval = ThermalAlertSettings.soundCooldown
    private(set) var lastSoundDate: Date?

    /// Returns whether an alert at `date` may sound, recording it when it may.
    /// A clock set backwards ends the window instead of muting alerts until
    /// the clock catches up again.
    mutating func allowsSound(at date: Date) -> Bool {
        if let lastSoundDate {
            let elapsed = date.timeIntervalSince(lastSoundDate)
            if elapsed >= 0, elapsed < cooldown { return false }
        }
        lastSoundDate = date
        return true
    }

    mutating func reset() {
        lastSoundDate = nil
    }
}

/// Plays system alert sounds, stopping the previous one so a preview
/// clicked twice restarts instead of being ignored while it still plays.
@MainActor
enum ThermalAlertSoundPlayer {
    private static var current: NSSound?

    /// Returns false when the sound could not be loaded or started.
    @discardableResult
    static func play(_ name: String) -> Bool {
        current?.stop()
        current = NSSound(named: NSSound.Name(name))
        return current?.play() ?? false
    }
}

enum ThermalSensor: String, CaseIterable, Hashable {
    case cpu
    case gpu

    var title: String {
        rawValue.uppercased()
    }

    func temperature(in reading: ThermalReading) -> Double? {
        switch self {
        case .cpu: reading.cpuCelsius
        case .gpu: reading.gpuCelsius
        }
    }
}

struct ThermalAlert: Equatable {
    let sensor: ThermalSensor
    let temperatureCelsius: Double
}

/// Tracks each sensor's high-temperature episode so one sustained spike does
/// not produce a notification every time the telemetry timer fires.
struct ThermalAlertMonitor {
    var thresholdCelsius: Double
    private(set) var alertedSensors: Set<ThermalSensor> = []

    mutating func alerts(for reading: ThermalReading) -> [ThermalAlert] {
        let hotSensors = Set(ThermalSensor.allCases.compactMap { sensor -> ThermalSensor? in
            guard let temperature = sensor.temperature(in: reading),
                  temperature >= thresholdCelsius else {
                return nil
            }
            return sensor
        })

        // A sensor can notify again only after it has returned below the
        // threshold and entered a new high-temperature episode.
        alertedSensors.formIntersection(hotSensors)
        let newSensors = hotSensors.subtracting(alertedSensors)
        alertedSensors.formUnion(newSensors)

        return ThermalSensor.allCases.compactMap { sensor in
            guard newSensors.contains(sensor),
                  let temperature = sensor.temperature(in: reading) else {
                return nil
            }
            return ThermalAlert(sensor: sensor, temperatureCelsius: temperature)
        }
    }

    mutating func reset() {
        alertedSensors.removeAll()
    }
}

/// Keeps local notifications visible even when the menu-bar app is active,
/// and hands notification buttons and clicks back to the controller.
final class ThermalNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    /// Receives the action identifier and the notification request identifier.
    var onResponse: ((String, String) -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        onResponse?(response.actionIdentifier, response.notification.request.identifier)
        completionHandler()
    }
}
