import SwiftUI

struct ProfileEditView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var confirmsDiscard = false

    private var editing: ProfileEditingState { app.profile.editing }
    private var draft: ProfileEditDraft? { editing.draft }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Avatar and cover uploads aren’t available yet.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Display name")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("Display name", text: displayNameBinding)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityIdentifier("profile.edit.displayName")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Bio")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("Bio", text: bioBinding, axis: .vertical)
                        .lineLimit(4...10)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(minHeight: 96, alignment: .topLeading)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityIdentifier("profile.edit.bio")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Visibility")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker("Visibility", selection: visibilityBinding) {
                        ForEach([ProfileVisibility.public, .followers, .teams, .private], id: \.self) { value in
                            Text(value.displayTitle).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("profile.edit.visibility")
                }

                statusRow

                Button {
                    Task {
                        let ok = await app.profile.saveEdits()
                        if ok {
                            app.navigation.close()
                        }
                    }
                } label: {
                    Text(editing.status == .saving ? "Saving…" : "Save")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(app.appearance.accent.color)
                .disabled(editing.status == .saving || draft?.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true)
                .accessibilityIdentifier("profile.edit.save")
            }
            .padding(.horizontal, ModulaLayout.contentInset)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .modulaCanvas()
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { attemptDismiss() }
                    .accessibilityIdentifier("profile.edit.cancel")
            }
        }
        .confirmationDialog("Discard changes?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) {
                app.profile.discardEditing()
                app.navigation.close()
            }
            Button("Keep Editing", role: .cancel) {}
        }
        .accessibilityIdentifier("profile.edit")
    }

    @ViewBuilder
    private var statusRow: some View {
        switch editing.status {
        case .saving:
            Label("Saving…", systemImage: "arrow.triangle.2.circlepath")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        case .saved:
            Label("Saved", systemImage: "checkmark.circle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(app.appearance.accent.color)
        case .failed:
            Label(editing.error ?? "Could not save profile.", systemImage: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.red)
        case .dirty:
            Text("Unsaved changes")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .idle:
            EmptyView()
        }
    }

    private var displayNameBinding: Binding<String> {
        Binding(
            get: { draft?.displayName ?? "" },
            set: { value in app.profile.updateEditingDraft { $0.displayName = value } }
        )
    }

    private var bioBinding: Binding<String> {
        Binding(
            get: { draft?.bio ?? "" },
            set: { value in app.profile.updateEditingDraft { $0.bio = value } }
        )
    }

    private var visibilityBinding: Binding<ProfileVisibility> {
        Binding(
            get: { draft?.visibility ?? .public },
            set: { value in app.profile.updateEditingDraft { $0.visibility = value } }
        )
    }

    private func attemptDismiss() {
        if editing.isDirty {
            confirmsDiscard = true
        } else {
            app.profile.discardEditing()
            app.navigation.close()
        }
    }
}
