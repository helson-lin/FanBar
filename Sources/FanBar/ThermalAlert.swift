import Foundation
import UserNotifications

enum ThermalAlertSettings {
    static let notificationsEnabledKey = "fanbar.highTemperatureNotificationsEnabled"
    static let thresholdCelsius = 90.0
    static let notificationIdentifierPrefix = "fanbar.high-temperature"
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
    let thresholdCelsius: Double
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

/// Keeps local notifications visible even when the menu-bar app is active.
final class ThermalNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
