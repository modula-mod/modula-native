import Charts
import SwiftUI

// MARK: - Creator Insights (`/v1/creator/insights`)

struct CreatorInsightsView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var window = 28
    @State private var insights: CreatorInsightsResponse?
    @State private var error: String?
    @State private var metric: Metric = .engagement
    @State private var revealed = false

    enum Metric: String, CaseIterable, Identifiable {
        case engagement = "Engagement", followers = "New followers", comments = "Comments", storyViews = "Story views"
        var id: String { rawValue }
        func value(_ point: CreatorInsightsResponse.Point) -> Int {
            switch self {
            case .engagement: point.engagement
            case .followers: point.newFollowers
            case .comments: point.comments
            case .storyViews: point.storyViews
            }
        }
    }

    var body: some View {
        SettingsScrollCanvas {
            Picker("Period", selection: $window) {
                Text("7 days").tag(7)
                Text("28 days").tag(28)
                Text("90 days").tag(90)
            }
            .pickerStyle(.segmented)
            if let insights {
                summary(insights)
                chart(insights)
                topPosts(insights)
                SettingsAPIFootnote(text: "Counted from real activity on your posts and profile, excluding your own. Modula doesn’t track \(Self.untrackedLabel(insights.notTracked)), so they aren’t shown or estimated.")
            } else if let error {
                ModulaEmptyState(title: "Insights unavailable", message: error, symbol: "chart.xyaxis.line")
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 240)
            }
        }
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: window) { await load() }
        .refreshable { await load() }
    }

    nonisolated static func untrackedLabel(_ keys: [String]) -> String {
        let names = keys.map { key -> String in
            switch key {
            case "impressions": "impressions"
            case "profileViews": "profile views"
            case "reach": "reach"
            default: key
            }
        }
        return ListFormatter.localizedString(byJoining: names)
    }

    private func summary(_ insights: CreatorInsightsResponse) -> some View {
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return LazyVGrid(columns: columns, spacing: 10) {
            SettingsStatChip(label: "Followers", value: insights.totals.followers.formatted(), symbol: "person.2")
            SettingsStatChip(label: "New followers", value: "+\(insights.totals.newFollowers.formatted())", symbol: "person.badge.plus")
            SettingsStatChip(label: "Likes & reactions", value: (insights.totals.likes + insights.totals.reactions).formatted(), symbol: "heart")
            SettingsStatChip(label: "Comments", value: insights.totals.comments.formatted(), symbol: "bubble.left")
            SettingsStatChip(label: "Shares & saves", value: (insights.totals.shares + insights.totals.saves).formatted(), symbol: "square.and.arrow.up")
            SettingsStatChip(label: "Posts", value: insights.totals.posts.formatted(), symbol: "square.and.pencil")
        }
    }

    private func chart(_ insights: CreatorInsightsResponse) -> some View {
        let values = insights.series.map(metric.value)
        let trend = CreatorInsightsResponse.trend(values)
        return SettingsGroup(title: metric.rawValue, subtitle: trend.map { Self.trendLabel($0) } ?? "Daily, \(window) days") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Metric", selection: $metric) {
                    ForEach(Metric.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                if values.allSatisfy({ $0 == 0 }) {
                    Text("Nothing yet in this period. Activity shows up here as soon as it happens.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    Chart(insights.series) { point in
                        BarMark(
                            x: .value("Day", point.day, unit: .day),
                            y: .value(metric.rawValue, revealed ? metric.value(point) : 0)
                        )
                        .foregroundStyle(app.appearance.accent.color.gradient)
                        .cornerRadius(3)
                    }
                    .chartYAxis { AxisMarks(position: .leading) }
                    .frame(height: 180)
                    .accessibilityLabel("\(metric.rawValue) per day")
                    .accessibilityValue("Total \(values.reduce(0, +)) over \(window) days")
                    .onAppear {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.6)) { revealed = true }
                    }
                }
            }
        }
    }

    nonisolated static func trendLabel(_ change: Double) -> String {
        let percent = Int((change * 100).rounded())
        if percent == 0 { return "Flat versus the first half of the period" }
        return "\(percent > 0 ? "Up" : "Down") \(abs(percent))% versus the first half of the period"
    }

    @ViewBuilder
    private func topPosts(_ insights: CreatorInsightsResponse) -> some View {
        SettingsGroup(title: "Top posts") {
            if insights.topPosts.isEmpty {
                Text("Posts you share in this period appear here, ranked by interactions.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(insights.topPosts.enumerated()), id: \.element.id) { index, post in
                        Button {
                            app.navigation.open(.post(post.postId, .root))
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(index + 1)").font(.headline.monospacedDigit()).foregroundStyle(.secondary).frame(width: 20)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(post.excerpt.isEmpty ? "Media post" : post.excerpt).font(.subheadline).lineLimit(2).foregroundStyle(.primary)
                                    Text("\(post.interactions) interactions · \(post.likes + post.reactions) likes · \(post.replies) replies")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if index < insights.topPosts.count - 1 { Divider() }
                    }
                }
            }
        }
    }

    private func load() async {
        guard app.auth.isSignedIn else { error = "Sign in to see insights."; return }
        do {
            let value = try await app.client.authenticatedJSON("GET", path: "/v1/creator/insights?days=\(window)")
            insights = try GreenfieldValueDecoder.decode(CreatorInsightsResponse.self, from: value)
            error = nil
        } catch {
            if insights == nil { self.error = "Couldn’t load insights. Pull to try again." }
        }
    }
}

// MARK: - Payouts ledger (`/v1/creator/payouts`)

struct PayoutsLedgerView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var ledger: PayoutsLedgerResponse?
    @State private var error: String?

    var body: some View {
        SettingsScrollCanvas {
            SettingsHeroBanner(title: "Payouts", subtitle: "Your earnings ledger. Every amount comes from a recorded entry.", symbol: "banknote")
            if let ledger {
                SettingsGroup(title: "Balance") {
                    if ledger.balances.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(SettingsMoney.format(minor: 0, currency: Locale.current.currency?.identifier ?? "GBP"))
                                .font(.largeTitle.weight(.semibold).monospacedDigit())
                            Text("No earnings recorded.").font(.subheadline).foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(ledger.balances) { balance in
                            LabeledContent(balance.currency, value: SettingsMoney.format(minor: balance.amountMinor, currency: balance.currency))
                        }
                    }
                }
                SettingsGroup(title: "Payout method") {
                    Label(ledger.provider == nil ? "Not connected" : "Connected", systemImage: ledger.payoutsEnabled ? "checkmark.seal" : "xmark.seal")
                        .foregroundStyle(ledger.payoutsEnabled ? .primary : .secondary)
                    if let reason = ledger.reason { Text(reason).font(.caption).foregroundStyle(.secondary) }
                }
                SettingsGroup(title: "Activity") {
                    if ledger.entries.isEmpty {
                        Text("Nothing yet. Earnings, fees and payouts will be listed here as they happen.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(ledger.entries) { entry in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.description).font(.subheadline)
                                        Text(SettingsISODate.parse(entry.occurredAt)?.formatted(date: .abbreviated, time: .omitted) ?? "")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(SettingsMoney.format(minor: entry.amountMinor, currency: entry.currency))
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundStyle(entry.amountMinor < 0 ? Color.secondary : Color.primary)
                                }
                                .padding(.vertical, 8)
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }
            } else if let error {
                SettingsAPIFootnote(text: error)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 160)
            }
        }
        .navigationTitle("Payouts")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard app.auth.isSignedIn else { error = "Sign in to see payouts."; return }
        do {
            let value = try await app.client.authenticatedJSON("GET", path: "/v1/creator/payouts")
            ledger = try GreenfieldValueDecoder.decode(PayoutsLedgerResponse.self, from: value)
            error = nil
        } catch {
            self.error = "Couldn’t load your ledger. Pull to try again."
        }
    }
}

// MARK: - Invoices (`/v1/commerce/invoices`)

struct InvoicesListView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var invoices: InvoicesResponse?
    @State private var error: String?

    var body: some View {
        List {
            if let invoices {
                if invoices.items.isEmpty {
                    ModulaEmptyState(title: "No invoices", message: "You haven’t been charged for anything on Modula. Invoices appear here if you ever are.", symbol: "doc.text")
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(invoices.items) { invoice in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(invoice.description).font(.subheadline.weight(.medium))
                                Text("\(invoice.number) · \(SettingsISODate.parse(invoice.issuedAt)?.formatted(date: .abbreviated, time: .omitted) ?? "")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(SettingsMoney.format(minor: invoice.totalMinor, currency: invoice.currency)).font(.subheadline.monospacedDigit())
                                Text(invoice.state.capitalized).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            } else if let error {
                Text(error).foregroundStyle(.secondary)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .modulaSoftScrollEdge()
        .navigationTitle("Invoices")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard app.auth.isSignedIn else { error = "Sign in to see invoices."; return }
        do {
            let value = try await app.client.authenticatedJSON("GET", path: "/v1/commerce/invoices")
            invoices = try GreenfieldValueDecoder.decode(InvoicesResponse.self, from: value)
            error = nil
        } catch {
            self.error = "Couldn’t load invoices. Pull to try again."
        }
    }
}
