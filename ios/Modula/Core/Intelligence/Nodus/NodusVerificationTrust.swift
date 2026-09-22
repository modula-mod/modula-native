import CryptoKit
import Foundation

enum NodusVerificationValidationError: Error, Sendable, Equatable {
    case unsupportedSchema
    case missionMismatch
    case questionMismatch
    case invalidConfidence
    case missingEvidence
    case unknownSigner
    case invalidSignature
}

struct NodusVerificationTrustStore: Sendable {
    private let publicKeys: [String: P256.Signing.PublicKey]

    init(publicKeys: [String: P256.Signing.PublicKey]) { self.publicKeys = publicKeys }

    func validate(_ result: NodusVerificationResult, mission: VerificationMissionDraft) throws {
        guard result.schemaVersion == 1 else { throw NodusVerificationValidationError.unsupportedSchema }
        guard result.provenance.missionID == mission.id.uuidString else { throw NodusVerificationValidationError.missionMismatch }
        guard Self.normalize(result.question) == Self.normalize(mission.question) else {
            throw NodusVerificationValidationError.questionMismatch
        }
        guard (0 ... 1).contains(result.confidence) else { throw NodusVerificationValidationError.invalidConfidence }
        if [.confirmed, .corrected, .partiallyCorrect].contains(result.result), result.sources.isEmpty {
            throw NodusVerificationValidationError.missingEvidence
        }
        guard let key = publicKeys[result.signerID] else { throw NodusVerificationValidationError.unknownSigner }
        let data = try Self.payloadData(result.signedPayload)
        guard let signature = try? P256.Signing.ECDSASignature(derRepresentation: result.signature),
              key.isValidSignature(signature, for: data) else {
            throw NodusVerificationValidationError.invalidSignature
        }
    }

    static func payloadData(_ payload: NodusVerificationResult.SignedPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(payload)
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
    }
}
