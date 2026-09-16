import SwiftUI

struct PollEditor: View {
    var poll: PollDraft
    var maxOptions: Int
    var onChange: (PollDraft) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Question", text: questionBinding, axis: .vertical)
                .font(.headline)
                .accessibilityIdentifier("compose.poll.question")
            ForEach(Array(poll.options.enumerated()), id: \.element.id) { index, option in
                HStack {
                    TextField("Option \(index + 1)", text: optionBinding(index))
                        .accessibilityLabel("Option \(index + 1)")
                        .accessibilityIdentifier("compose.poll.option.\(index)")
                    if poll.options.count > PollDraft.minimumOptions {
                        Button("Remove", systemImage: "minus.circle") {
                            remove(at: index)
                        }
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("Remove option \(index + 1)")
                    }
                    if index > 0 {
                        Button("Move up", systemImage: "arrow.up") {
                            move(index, earlier: true)
                        }
                        .labelStyle(.iconOnly)
                    }
                    if index < poll.options.count - 1 {
                        Button("Move down", systemImage: "arrow.down") {
                            move(index, earlier: false)
                        }
                        .labelStyle(.iconOnly)
                    }
                }
            }
            if poll.options.count < maxOptions {
                Button("Add option") { addOption() }
                    .accessibilityIdentifier("compose.poll.add")
            }
            Stepper(value: durationBinding, in: 1...max(1, poll.durationHours + 168)) {
                Text("Duration \(poll.durationHours) hours")
            }
            .fontDesign(.default)
            Text("Votes, counts, and expiry are owned by Greenfield when polls are enabled.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
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

    private var durationBinding: Binding<Int> {
        Binding(
            get: { poll.durationHours },
            set: { value in
                var next = poll
                next.durationHours = value
                onChange(next)
            }
        )
    }

    private func optionBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { poll.options[index].text },
            set: { value in
                var next = poll
                next.options[index].text = value
                onChange(next)
            }
        )
    }

    private func addOption() {
        var next = poll
        next.options.append(.init(id: UUID().uuidString, text: ""))
        onChange(next)
    }

    private func remove(at index: Int) {
        var next = poll
        next.options.remove(at: index)
        onChange(next)
    }

    private func move(_ index: Int, earlier: Bool) {
        var next = poll
        let target = earlier ? index - 1 : index + 1
        guard next.options.indices.contains(target) else { return }
        next.options.swapAt(index, target)
        onChange(next)
    }
}
