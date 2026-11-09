import Foundation
import Security

/// Reads the running process's own code signature.
public enum OwnCodeSignature {
    /// The signing team, or nil for unsigned and ad-hoc builds.
    public static func teamIdentifier() -> String? {
        var ownCode: SecCode?
        guard SecCodeCopySelf([], &ownCode) == errSecSuccess,
              let ownCode
        else { return nil }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(ownCode, [], &staticCode) == errSecSuccess,
              let staticCode
        else { return nil }

        var signingInformation: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInformation
        ) == errSecSuccess,
            let information = signingInformation as? [CFString: Any]
        else { return nil }
        return information[kSecCodeInfoTeamIdentifier] as? String
    }
}
