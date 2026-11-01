import SwiftUI

/// Creator / publish: the manifest checklist, the developer's real submissions and the Premium
/// gate for paid games. Builds and releases stay in Developer Studio.
struct GubicCreatorView: View {
    let store: GubicStore
    @Environment(AppEnvironment.self) private var app
    @State private var publishers: [String] = []
    @State private var submissions: [GubicSubmission] = []
    @State private var state: GubicLoadState = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: ModulaSpacing.lg) {
            VStack(alignment: .leading, spacing: ModulaSpacing.xs) {
                Text("Make a game").font(.title3.bold())
                Text("Build an HTML5 or Phaser game, release it from Developer Studio, then submit it to GUBIC for review. Free games can be published on every plan.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            checklist
            ModulaButton(title: "Open Developer Studio", symbol: "hammer") { app.navigation.open(.developer(.studio)) }
                .accessibilityIdentifier("gubic.create.studio")
            monetisation
            Text("Your submissions").font(.title3.bold())
            submissionsList
        }
        .task { await load() }
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: ModulaSpacing.sm) {
            Text("Package checklist (gubic.game.json)").font(.headline)
            ForEach(Self.rules, id: \.self) { rule in
                Label(rule, systemImage: "checkmark.circle").font(.subheadline)
                    .foregroundStyle(.primary)
                    .symbolRenderingMode(.hierarchical)
            }
            Text("Retro emulation and MMORPG runtimes are planned for later and aren't accepted yet.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(ModulaSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modulaGlass(in: RoundedRectangle(cornerRadius: ModulaRadius.large, style: .continuous), interactive: false)
    }

    static let rules = [
        "Engine: HTML5 canvas, Phaser or PlayCanvas, entry index.html",
        "Strict CSP: no network (connect-src 'none'), no remote scripts",
        "Bridge v1: lifecycle, plus score, achievements or lobby if used",
        "Up to 100 achievements, 1,000 points in total",
        "Multiplayer through GUBIC lobbies only, 2 to 16 players",
        "Age rating 4+, 9+, 12+ or 17+; package up to 64 MB",
    ]

    @ViewBuilder private var monetisation: some View {
        let allowed = store.capabilities.allows("gubic_creator_monetisation")
        VStack(alignment: .leading, spacing: ModulaSpacing.xs) {
            Label(allowed ? "Paid games available on your plan" : "Paid games and in-game purchases",
                  systemImage: allowed ? "checkmark.seal" : "lock").font(.headline)
            if !allowed {
                GubicPremiumNote(text: store.capabilities.loaded
                    ? "Paid games need Modula Horizon Plus. Free games can be published on every plan."
                    : "Plan details couldn't be loaded, so paid publishing stays locked. Free games can be published on every plan.")
            }
        }
    }

    @ViewBuilder private var submissionsList: some View {
        if state == .loading {
            ModulaLoadingState(title: "Loading submissions…")
        } else if state != .loaded {
            GubicStateView(state: state, emptyTitle: "", emptyMessage: "", retry: { Task { await load() } })
        } else if publishers.isEmpty {
            GubicStateView(state: .loaded, emptyTitle: "No publisher yet",
                           emptyMessage: "Create a publisher and a game product in Developer Studio first.", symbol: "person.badge.plus")
        } else if submissions.isEmpty {
            GubicStateView(state: .loaded, emptyTitle: "No submissions yet",
                           emptyMessage: "Submissions you send for review show up here with their status.", symbol: "tray")
        } else {
            ForEach(submissions) { item in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(item.title).font(.headline)
                        Spacer()
                        Text(item.status.capitalized).font(.caption.weight(.semibold))
                            .padding(.horizontal, ModulaSpacing.sm).padding(.vertical, 4)
                            .modulaGlass(in: Capsule(), interactive: false, tint: app.appearance.liveAccent.opacity(0.2))
                    }
                    Text("\(item.version) · \(item.monetisation)").font(.subheadline).foregroundStyle(.secondary)
                    if let reason = item.decisionReason { Text(reason).font(.footnote).foregroundStyle(.secondary) }
                }
                .padding(.vertical, ModulaSpacing.xs)
            }
        }
    }

    private func load() async {
        state = .loading
        do {
            publishers = try await store.publisherIDs()
            var all: [GubicSubmission] = []
            for publisher in publishers { all += try await store.submissions(publisher: publisher) }
            submissions = all
            state = .loaded
        } catch {
            state = .from(error)
        }
    }
}
