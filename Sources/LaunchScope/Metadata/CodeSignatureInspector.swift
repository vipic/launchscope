import Foundation
import Security

struct CodeSignatureInspector: Sendable {
    func inspect(path: String?) -> SignatureInfo {
        guard let path,
              PathAccessPolicy.canProbeMetadata(at: path),
              FileManager.default.fileExists(atPath: path) else { return SignatureInfo() }

        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(
            URL(fileURLWithPath: path) as CFURL,
            SecCSFlags(),
            &staticCode
        )
        guard createStatus == errSecSuccess, let staticCode else {
            return SignatureInfo(kind: createStatus == errSecCSUnsigned ? .unsigned : .unavailable, statusCode: createStatus)
        }

        let validityStatus = SecStaticCodeCheckValidity(staticCode, SecCSFlags(), nil)
        var information: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
        let dictionary = information as? [String: Any] ?? [:]
        let identifier = dictionary[kSecCodeInfoIdentifier as String] as? String
        let teamIdentifier = dictionary[kSecCodeInfoTeamIdentifier as String] as? String
        let certificates = dictionary[kSecCodeInfoCertificates as String] as? [SecCertificate] ?? []
        let authorities = certificates.compactMap {
            SecCertificateCopySubjectSummary($0) as String?
        }

        let kind: SignatureKind
        if validityStatus == errSecCSUnsigned {
            kind = .unsigned
        } else if validityStatus != errSecSuccess {
            kind = .invalid
        } else if Self.satisfiesRequirement(staticCode, "anchor apple") {
            kind = .apple
        } else if Self.satisfiesRequirement(staticCode, "anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.9] exists") {
            kind = .appStore
        } else if Self.satisfiesRequirement(staticCode, "anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists") {
            kind = .developerID
        } else if dictionary[kSecCodeInfoFlags as String] != nil {
            kind = .adHoc
        } else {
            kind = .unavailable
        }

        return SignatureInfo(
            kind: kind,
            identifier: identifier,
            teamIdentifier: teamIdentifier,
            authorities: authorities,
            statusCode: infoStatus == errSecSuccess ? validityStatus : infoStatus
        )
    }

    private static func satisfiesRequirement(_ code: SecStaticCode, _ expression: String) -> Bool {
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(expression as CFString, SecCSFlags(), &requirement) == errSecSuccess,
              let requirement else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(), requirement) == errSecSuccess
    }
}
