import Foundation

struct NodusConfidenceSignals: Sendable, Equatable {
    let freshness: NodusFreshness
    let domainPerformance: Double?
    let modelConsistency: Double?
    let generationCompleted: Bool
    let structuredOutputValid: Bool?
    let localEvidenceCoverage: Double?
    let explicitUncertainty: Bool
    let highRiskClaim: Bool
}

/// Confidence is calculated outside generation. It is an estimate calibrated by held-out
/// evaluation, never a model-authored percentage presented as truth.
struct NodusConfidenceEngine: Sendable {
    func evaluate(_ signals: NodusConfidenceSignals) -> NodusConfidence {
        var answer = signals.domainPerformance ?? 0.58
        if let consistency = signals.modelConsistency { answer = answer * 0.7 + consistency * 0.3 }
        if !signals.generationCompleted { answer -= 0.28 }
        if signals.structuredOutputValid == false { answer -= 0.32 }
        if signals.explicitUncertainty { answer -= 0.12 }
        if signals.highRiskClaim { answer -= 0.16 }

        let evidence = signals.localEvidenceCoverage ?? 0.18
        let freshness: Double = switch signals.freshness {
        case .stable: 0.94
        case .possiblyStale: 0.48
        case .currentDataRequired: 0.04
        case .unknown: 0.32
        }
        if signals.freshness == .currentDataRequired { answer = min(answer, 0.38) }

        let band: NodusConfidenceBand
        if freshness < 0.15 || signals.highRiskClaim { band = .needsVerification }
        else if answer >= 0.78 { band = .high }
        else if answer >= 0.52 { band = .medium }
        else { band = .low }
        return NodusConfidence(answer: answer, evidence: evidence, freshness: freshness, band: band)
    }
}
