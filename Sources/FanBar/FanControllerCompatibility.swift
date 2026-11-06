import Foundation

extension FanController {
    var compatibilitySnapshot: CompatibilitySnapshot? {
        guard let observation = compatibilityObservation else { return nil }
        return CompatibilitySnapshot.make(
            device: compatibilityDevice,
            observation: observation,
            helperState: helperState,
            manualEvidence: manualControlEvidence,
            curveEvidence: curveControlEvidence,
            manualFailure: manualControlFailure,
            curveFailure: curveControlFailure,
            curveSensor: curveProfile.sensor
        )
    }
}
