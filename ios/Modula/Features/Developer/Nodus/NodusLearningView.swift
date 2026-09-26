import SwiftUI

#if DEBUG
struct NodusLearningView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var candidates: [NodusLearningCandidate] = []

    var body: some View {
        List {
            candidateSection("Observed failures", candidates.filter { $0.trainingEligibility == .ineligible })
            candidateSection("Pending review", candidates.filter { $0.trainingEligibility == .pendingReview })
            candidateSection("Approved candidates", candidates.filter { $0.trainingEligibility == .approved })
            candidateSection("Rejected candidates", candidates.filter { $0.trainingEligibility == .rejected })
            Section("Governance") {
                Text("Corrections are local Learning Candidates. Valid correction, privacy eligibility, consent, review, and approval are required before future dataset use. This screen never starts training or updates R7 weights.")
                    .font(.footnote).foregroundStyle(.secondary)
                ShareLink(item: app.nodusVerificationStore.approvedExportURL) {
                    Label("Export Approved JSONL", systemImage: "square.and.arrow.up")
                }
            }
        }
        .modulaSoftScrollEdge()
        .navigationTitle("Learning")
        .task { await refresh() }
        .accessibilityIdentifier("nodus.learning")
    }

    @ViewBuilder
    private func candidateSection(_ title: String, _ values: [NodusLearningCandidate]) -> some View {
        Section(title) {
            if values.isEmpty { Text("None").foregroundStyle(.secondary) }
            ForEach(values) { candidate in
                VStack(alignment: .leading, spacing: 6) {
                    Text(candidate.question).font(.body.weight(.medium))
                    Text("Nodus: \(candidate.originalAnswer)").font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    Text("Correction: \(candidate.verifiedAnswer)").font(.caption).lineLimit(4)
                    HStack {
                        Text(candidate.rating?.displayName ?? candidate.result.rawValue)
                        Text(candidate.privacyClass.rawValue)
                        Text(candidate.globalTrainingConsent ? "Consent" : "No global consent")
                    }
                    .font(.caption2).foregroundStyle(.secondary)
                    if candidate.trainingEligibility == .pendingReview {
                        HStack {
                            Button("Approve") { Task { _ = try? await app.nodusVerificationStore.reviewCandidate(id: candidate.id, approve: true); await refresh() } }
                                .buttonStyle(.bordered).controlSize(.small)
                            Button("Reject", role: .destructive) { Task { _ = try? await app.nodusVerificationStore.reviewCandidate(id: candidate.id, approve: false); await refresh() } }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                }
                .padding(.vertical, 3)
            }
        }
    }

    private func refresh() async {
        candidates = await app.nodusVerificationStore.snapshot().learningCandidates
            .sorted { $0.createdAt > $1.createdAt }
    }
}
#endif
