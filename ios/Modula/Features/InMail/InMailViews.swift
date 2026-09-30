import SwiftUI

struct InMailRouteView: View {
    let route: InMailRoute

    var body: some View {
        switch route {
        case .inbox: InMailInboxView()
        case .compose: InMailComposer()
        case .thread(let id): InMailThreadView(threadID: id)
        }
    }
}

struct InMailInboxView: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            MessagesScopePicker(selection: .inMail)
            search
            content
        }
        .modulaSoftScrollEdge()
        .navigationTitle("In-Mail")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    app.navigation.push(.messages(.inMail(.compose)))
                    HapticEngine.shared.play(.navigation)
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("New In-Mail")
            }
        }
        .task { await app.inMail.loadIfNeeded() }
        .refreshable { await app.inMail.refresh() }
        .accessibilityIdentifier("inmail.inbox")
        .accessibilityValue(RouteSerializer.serialize(.messages(.inMail(.inbox))))
    }

    private var search: some View {
        VStack(alignment: .leading, spacing: 6) {
            ModulaSearchField(text: Bindable(app.inMail).query, prompt: "Search In-Mail")
            if !app.inMail.query.isEmpty, !app.inMail.capabilities.serverSearch {
                Text("Searches loaded threads only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, ModulaLayout.contentInset)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        let items = app.inMail.visibleThreads
        switch app.inMail.loadState {
        case .loading where items.isEmpty:
            ModulaLoadingState(title: "Loading In-Mail")
        case .failed(let message) where items.isEmpty:
            ModulaErrorState(message: message) { Task { await app.inMail.refresh() } }
        case _ where !app.inMail.capabilities.list && items.isEmpty:
            ModulaEmptyState(
                title: "In-Mail",
                message: "Structured messages will appear here when In-Mail is available.",
                symbol: "envelope"
            )
        case _ where items.isEmpty:
            ModulaEmptyState(title: "No In-Mail yet", message: "Professional and long-form messages will live here.", symbol: "envelope")
        default:
            List(items) { thread in
                Button {
                    app.navigation.push(.messages(.inMail(.thread(thread.id))))
                    HapticEngine.shared.play(.navigation)
                } label: {
                    InMailRow(thread: thread)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .modulaSoftScrollEdge()
        }
    }
}

struct InMailRow: View {
    let thread: InMailThread

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if thread.unread {
                    UnreadBadge(count: 1)
                }
                Text(thread.participants.first?.displayName ?? "In-Mail")
                    .font(.subheadline.weight(thread.unread ? .semibold : .regular))
                Spacer()
                Text(ConversationRow.relative(thread.updatedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(thread.subject)
                .font(.body.weight(thread.unread ? .semibold : .regular))
                .fixedSize(horizontal: false, vertical: true)
            Text(thread.preview)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([
            thread.unread ? "Unread" : "Read",
            thread.participants.first?.displayName ?? "In-Mail",
            thread.subject,
            thread.preview,
            ConversationRow.relative(thread.updatedAt)
        ].joined(separator: ", "))
        .accessibilityIdentifier("inmail.row.\(thread.id)")
    }
}

struct InMailThreadView: View {
    let threadID: InMailThreadID
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                ForEach(app.inMail.messages[threadID] ?? []) { message in
                    article(message)
                    Divider().opacity(0.35)
                }
                reply
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.vertical, 16)
        }
        .modulaSoftScrollEdge()
        .navigationTitle(thread?.subject ?? "In-Mail")
        .navigationBarTitleDisplayMode(.inline)
        .task { await app.inMail.loadThread(threadID) }
        .accessibilityIdentifier("inmail.thread.\(threadID)")
    }

    private var thread: InMailThread? { app.inMail.thread(id: threadID) }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(thread?.subject ?? "In-Mail")
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(participantLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var participantLine: String {
        let names = (thread?.participants ?? []).map(\.displayName)
        if names.isEmpty { return "Participants unavailable" }
        return names.joined(separator: ", ")
    }

    private func article(_ message: InMailMessage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(message.sender.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(ConversationRow.relative(message.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(message.body)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(message.sender.displayName), \(ConversationRow.relative(message.createdAt)), \(message.body)")
    }

    private var reply: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reply")
                .font(.headline)
            TextField("Write a reply", text: replyBinding, axis: .vertical)
                .lineLimit(3...10)
                .padding(12)
                .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 88 : 72, alignment: .topLeading)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .disabled(!app.inMail.capabilities.reply)
            Button("Send reply") {
                Task { await app.inMail.reply(to: threadID) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!app.inMail.capabilities.reply)
        }
    }

    private var replyBinding: Binding<String> {
        Binding(
            get: { app.inMail.replyDrafts[threadID] ?? "" },
            set: { app.inMail.replyDrafts[threadID] = $0 }
        )
    }
}

struct InMailComposer: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        @Bindable var mail = app.inMail
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                field(title: "To") {
                    TextField("Handle", text: $mail.draft.toHandle)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("inmail.compose.to")
                }
                field(title: "Subject") {
                    TextField("Subject", text: $mail.draft.subject)
                        .accessibilityIdentifier("inmail.compose.subject")
                }
                field(title: "Message") {
                    TextField("Message", text: $mail.draft.body, axis: .vertical)
                        .lineLimit(6...16)
                        .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 160 : 140, alignment: .topLeading)
                        .accessibilityIdentifier("inmail.compose.body")
                }
                if let error = mail.sendError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Button {
                    Task {
                        if let thread = await app.inMail.sendDraft() {
                            app.drafts.discardInMail()
                            app.navigation.replaceTop(with: .messages(.inMail(.thread(thread.id))))
                        }
                    }
                } label: {
                    Text(mail.sendState == .sending ? "Sending…" : "Send")
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(mail.sendState == .sending || !mail.capabilities.send)
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.vertical, 16)
        }
        .modulaSoftScrollEdge()
        .navigationTitle("New In-Mail")
        .accessibilityIdentifier("inmail.compose")
        .onChange(of: mail.draft) { _, draft in
            app.drafts.upsertInMail(draft)
        }
        .overlay(alignment: .top) {
            if let error = app.drafts.saveError {
                Text(error)
                    .font(.caption)
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            } else if app.drafts.showSavedIndicator {
                Text("Draft saved")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 8)
                    .accessibilityLabel("Draft saved")
            }
        }
        .onAppear {
            if let persisted = app.drafts.inMailDraft(),
               mail.draft.toHandle.isEmpty,
               mail.draft.subject.isEmpty,
               mail.draft.body.isEmpty {
                mail.draft = persisted.asComposerDraft()
            }
        }
        .accessibilityValue(RouteSerializer.serialize(.messages(.inMail(.compose))))
    }

    private func field<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content()
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minHeight: 44, alignment: .leading)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}
