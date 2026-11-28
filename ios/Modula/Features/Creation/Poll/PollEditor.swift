import SwiftUI

/// Composer poll card: glass card, lettered option rows, quick duration chips and add/remove animations.
/// Bindings are index-safe: a row being removed can't read past the end of the options array.
struct PollEditor: View {
    var poll: PollDraft
    var maxOptions: Int
    var onChange: (PollDraft) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let optionLimit = 80
    private static let durations: [(Int, String)] = [(1, "1h"), (6, "6h"), (24, "1 day"), (72, "3 days"), (168, "7 days")]

    private var spring: Animation? { reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.xaxis").font(.subheadline.weight(.bold))
                Text("Poll").font(.subheadline.weight(.bold))
                Spacer()
                Text("\(poll.options.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }.count)/\(poll.options.count) options")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary).monospacedDigit()
                    .contentTransition(.numericText())
            }
            TextField("Ask a question", text: questionBinding, axis: .vertical)
                .font(.headline)
                .lineLimit(1...3)
                .accessibilityIdentifier("compose.poll.question")
            ForEach(Array(poll.options.enumerated()), id: \.element.id) { index, option in
                HStack(spacing: 10) {
                    Text(Self.letter(index))
                        .font(.caption.weight(.heavy)).foregroundStyle(Color.modulaOnPrimary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.modulaPrimaryFill))
                    TextField("Option \(index + 1)", text: optionBinding(id: option.id))
                        .accessibilityLabel("Option \(index + 1)")
                        .accessibilityIdentifier("compose.poll.option.\(index)")
                    if option.text.count > Self.optionLimit - 15 {
                        Text("\(Self.optionLimit - option.text.count)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Menu {
                        if index > 0 { Button("Move Up", systemImage: "arrow.up") { move(id: option.id, earlier: true) } }
                        if index < poll.options.count - 1 { Button("Move Down", systemImage: "arrow.down") { move(id: option.id, earlier: false) } }
                        if poll.options.count > PollDraft.minimumOptions {
                            Button("Remove", systemImage: "minus.circle", role: .destructive) { remove(id: option.id) }
                        }
                    } label: {
                        Image(systemName: "ellipsis").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                            .frame(width: 32, height: 32).contentShape(Rectangle())
                    }
                    .accessibilityLabel("Option \(index + 1) actions")
                }
                .padding(.horizontal, 10).frame(minHeight: 46)
                .modulaGlass(in: Capsule(), interactive: false)
                .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .scale(scale: 0.9).combined(with: .opacity)))
            }
            if poll.options.count < maxOptions {
                Button { addOption() } label: {
                    Label("Add option", systemImage: "plus").font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                        .contentShape(Capsule())
                }
                .buttonStyle(ModulaPressStyle(scale: 0.97))
                .foregroundStyle(.primary)
                .accessibilityIdentifier("compose.poll.add")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Poll length").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(Self.durations, id: \.0) { hours, title in
                            let on = poll.durationHours == hours
                            Button {
                                var next = poll; next.durationHours = hours
                                withAnimation(spring) { onChange(next) }
                                HapticEngine.shared.play(.selection)
                            } label: {
                                Text(title).font(.caption.weight(.semibold))
                                    .foregroundStyle(on ? Color.modulaOnPrimary : Color.primary)
                                    .padding(.horizontal, 12).frame(height: 30)
                                    .background(Capsule().fill(on ? AnyShapeStyle(Color.modulaPrimaryFill) : AnyShapeStyle(Color.primary.opacity(0.07))))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                        if !Self.durations.contains(where: { $0.0 == poll.durationHours }) {
                            Text("\(poll.durationHours)h").font(.caption.weight(.semibold))
                                .padding(.horizontal, 12).frame(height: 30)
                                .background(Capsule().fill(Color.modulaPrimaryFill)).foregroundStyle(Color.modulaOnPrimary)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            Text("People can vote once the poll is posted.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: false)
        .animation(spring, value: poll.options.map(\.id))
        .accessibilityElement(children: .contain)
    }

    private static func letter(_ i: Int) -> String {
        let letters = Array("ABCDEFGHIJ")
        return letters.indices.contains(i) ? String(letters[i]) : "\(i + 1)"
    }

    private var questionBinding: Binding<String> {
        Binding(
            get: { poll.question },
            set: { value in
                var next = poll
                next.question = value
                onChange(next)
            }
        )
    }

    /// Looked up by id, not index: safe while a removed row animates out.
    private func optionBinding(id: String) -> Binding<String> {
        Binding(
            get: { poll.options.first(where: { $0.id == id })?.text ?? "" },
            set: { value in
                var next = poll
                guard let i = next.options.firstIndex(where: { $0.id == id }) else { return }
                next.options[i].text = String(value.prefix(Self.optionLimit))
                onChange(next)
            }
        )
    }

    private func addOption() {
        var next = poll
        next.options.append(.init(id: UUID().uuidString, text: ""))
        withAnimation(spring) { onChange(next) }
        HapticEngine.shared.play(.selection)
    }

    private func remove(id: String) {
        var next = poll
        guard next.options.count > PollDraft.minimumOptions else { return }
        next.options.removeAll { $0.id == id }
        withAnimation(spring) { onChange(next) }
    }

    private func move(id: String, earlier: Bool) {
        var next = poll
        guard let index = next.options.firstIndex(where: { $0.id == id }) else { return }
        let target = earlier ? index - 1 : index + 1
        guard next.options.indices.contains(target) else { return }
        next.options.swapAt(index, target)
        withAnimation(spring) { onChange(next) }
    }
}
