import SwiftUI
import UIKit

/// Portable structured document used by `ui.richText@1`.
/// Unknown block kinds stay in the serialized document and are not flattened to plain text.
struct StructuredDocument: Equatable {
    static let schema = "1.0.0"
    static let maxBlocks = 500
    static let editableTypes: Set<String> = [
        "paragraph", "heading", "quote", "code", "callout", "bullet-list", "numbered-list", "checklist",
    ]

    var schemaVersion: String
    var blocks: [JSONValue]

    enum ReadError: Error, Equatable {
        case unreadable
        case tooLarge
    }

    static func parse(_ raw: String) throws -> StructuredDocument {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return StructuredDocument(schemaVersion: schema, blocks: [paragraph(id: "block-1", text: "")])
        }
        guard trimmed.utf8.count <= 250_000 else { throw ReadError.tooLarge }
        if trimmed.hasPrefix("{"),
           let data = trimmed.data(using: .utf8),
           let value = try? JSONDecoder().decode(JSONValue.self, from: data),
           value["blocks"] != nil || value["schemaVersion"] != nil {
            guard value["schemaVersion"]?.string == schema else { throw ReadError.unreadable }
            let blocks = value["blocks"]?.array ?? []
            guard blocks.count <= maxBlocks else { throw ReadError.tooLarge }
            guard blocks.allSatisfy({ $0["id"]?.string?.isEmpty == false && $0["type"]?.string?.isEmpty == false }) else {
                throw ReadError.unreadable
            }
            return StructuredDocument(schemaVersion: schema, blocks: blocks)
        }
        let parts = trimmed.components(separatedBy: "\n\n")
        let blocks = parts.enumerated().map { index, text in paragraph(id: "block-\(index + 1)", text: text) }
        return StructuredDocument(schemaVersion: schema, blocks: blocks.isEmpty ? [paragraph(id: "block-1", text: "")] : blocks)
    }

    func serialize() -> String {
        let payload = JSONValue.object([
            "blocks": .array(blocks),
            "schemaVersion": .string(schemaVersion),
        ])
        guard JSONSerialization.isValidJSONObject(payload.foundation),
              let data = try? JSONSerialization.data(withJSONObject: payload.foundation, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    func blockID(_ block: JSONValue) -> String { block["id"]?.string ?? "" }
    func blockType(_ block: JSONValue) -> String { block["type"]?.string ?? "unknown" }

    func visibleText(_ block: JSONValue) -> String {
        if let items = block["items"]?.array?.compactMap(\.string) { return items.joined(separator: "\n") }
        if let inlines = block["inlines"]?.array, !inlines.isEmpty {
            return inlines.compactMap { $0["text"]?.string }.joined()
        }
        return block["text"]?.string ?? block["title"]?.string ?? ""
    }

    func plainText() -> String {
        blocks.map { block in
            blockType(block) == "divider" ? "" : visibleText(block)
        }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func replacingText(_ newText: String, blockID: String) -> StructuredDocument {
        var copy = self
        copy.blocks = blocks.map { block in
            guard self.blockID(block) == blockID, Self.editableTypes.contains(blockType(block)),
                  case .object(var fields) = block else { return block }
            let type = blockType(block)
            if type == "bullet-list" || type == "numbered-list" || type == "checklist" {
                let items = newText.split(separator: "\n", omittingEmptySubsequences: false).map { JSONValue.string(String($0)) }
                fields["items"] = .array(items)
                if type == "checklist" {
                    let old = fields["checked"]?.array ?? []
                    fields["checked"] = .array((0..<items.count).map { index in index < old.count ? old[index] : .bool(false) })
                }
            } else if fields["inlines"] != nil, visibleText(block) != newText {
                fields["inlines"] = .array([.object(["text": .string(newText)])])
                fields.removeValue(forKey: "text")
            } else if fields["inlines"] == nil {
                fields["text"] = .string(newText)
            }
            return .object(fields)
        }
        return copy
    }

    func applying(command: String, id: String, selection: NSRange) -> StructuredDocument {
        guard let index = blocks.firstIndex(where: { self.blockID($0) == id }) else { return self }
        let block = blocks[index]
        guard Self.editableTypes.contains(blockType(block)) else { return self }
        let source = visibleText(block)
        var copy = self
        switch command {
        case "heading":
            copy.blocks[index] = Self.paragraph(id: id, text: source, type: "heading", level: 2)
        case "quote":
            copy.blocks[index] = Self.paragraph(id: id, text: source, type: "quote")
        case "code":
            copy.blocks[index] = Self.paragraph(id: id, text: source, type: "code")
        case "bulletList", "list":
            copy.blocks[index] = Self.list(id: id, type: "bullet-list", items: source.isEmpty ? [""] : source.components(separatedBy: "\n"))
        case "numberedList":
            copy.blocks[index] = Self.list(id: id, type: "numbered-list", items: source.isEmpty ? [""] : source.components(separatedBy: "\n"))
        case "bold", "italic", "strikethrough":
            copy.blocks[index] = Self.marked(id: id, type: blockType(block), text: source, selection: selection, mark: command)
        default:
            return self
        }
        return copy
    }

    func insertingParagraph(after blockID: String, text: String = "") -> StructuredDocument {
        var copy = self
        let block = Self.paragraph(id: Self.freshID(existing: blocks), text: text)
        if let index = blocks.firstIndex(where: { self.blockID($0) == blockID }) {
            copy.blocks.insert(block, at: index + 1)
        } else {
            copy.blocks.append(block)
        }
        return copy
    }

    func splitting(blockID: String, at utf16Location: Int) -> (StructuredDocument, String) {
        guard let index = blocks.firstIndex(where: { self.blockID($0) == blockID }) else {
            let inserted = insertingParagraph(after: blockID)
            return (inserted, self.blockID(inserted.blocks.last ?? .null))
        }
        let source = visibleText(blocks[index]) as NSString
        let location = min(max(0, utf16Location), source.length)
        let head = source.substring(to: location)
        let tail = source.substring(from: location)
        var copy = replacingText(head, blockID: blockID)
        let created = copy.insertingParagraph(after: blockID, text: tail)
        let newID = created.blocks.dropFirst(index + 1).first.map(created.blockID) ?? blockID
        return (created, newID)
    }

    static func paragraph(id: String, text: String, type: String = "paragraph", level: Int? = nil) -> JSONValue {
        var fields: [String: JSONValue] = ["id": .string(id), "type": .string(type), "text": .string(text)]
        if let level { fields["level"] = .number(Double(level)) }
        return .object(fields)
    }

    static func list(id: String, type: String, items: [String]) -> JSONValue {
        .object([
            "id": .string(id),
            "items": .array(items.map(JSONValue.string)),
            "type": .string(type),
        ])
    }

    static func marked(id: String, type: String, text: String, selection: NSRange, mark: String) -> JSONValue {
        let ns = text as NSString
        let location = min(max(0, selection.location), ns.length)
        let length = min(max(0, selection.length), ns.length - location)
        let ranges: [(NSRange, Bool)]
        if length == 0 {
            ranges = [(NSRange(location: 0, length: ns.length), true)]
        } else {
            ranges = [
                (NSRange(location: 0, length: location), false),
                (NSRange(location: location, length: length), true),
                (NSRange(location: location + length, length: ns.length - location - length), false),
            ].filter { $0.0.length > 0 }
        }
        let inlines: [JSONValue] = ranges.map { range, marked in
            var fields: [String: JSONValue] = ["text": .string(ns.substring(with: range))]
            if marked { fields["marks"] = .array([.object(["type": .string(mark)])]) }
            return .object(fields)
        }
        return .object(["id": .string(id), "inlines": .array(inlines), "type": .string(type)])
    }

    private static func freshID(existing: [JSONValue]) -> String {
        let used = Set(existing.compactMap { $0["id"]?.string })
        var candidate = "block-\(UUID().uuidString.prefix(8).lowercased())"
        while used.contains(candidate) {
            candidate = "block-\(UUID().uuidString.prefix(8).lowercased())"
        }
        return candidate
    }
}

struct StructuredDocumentEditor: View {
    @Binding var text: String
    var capability: String
    var externalCommand: String?
    @State private var document: StructuredDocument?
    @State private var loadError: String?
    @State private var preservedSource: String?
    @State private var undoStack: [String] = []
    @State private var redoStack: [String] = []
    @State private var focusedID: String?
    @State private var selection = NSRange(location: 0, length: 0)
    @State private var appliedCommand: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Document")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Undo") { undo() }.disabled(undoStack.isEmpty).accessibilityIdentifier("product-ui.richtext.undo")
                Button("Redo") { redo() }.disabled(redoStack.isEmpty).accessibilityIdentifier("product-ui.richtext.redo")
            }
            commandBar
            if let loadError {
                Label(loadError, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("product-ui.richtext.error")
                if let preservedSource {
                    Text(preservedSource)
                        .font(.footnote)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("product-ui.richtext.preserved")
                }
            } else if let document {
                let stack = document.blocks.count > 40
                Group {
                    if stack {
                        LazyVStack(alignment: .leading, spacing: 8) { blockList(document) }
                    } else {
                        VStack(alignment: .leading, spacing: 8) { blockList(document) }
                    }
                }
            }
            Text("Stored as structured blocks for \(capability). Unsupported blocks stay in the document.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("product-ui.richtext")
        .onAppear(perform: load)
        .onChange(of: text) { _, _ in
            if document?.serialize() != text { load() }
        }
        .onChange(of: externalCommand) { _, command in
            guard let command, command != appliedCommand else { return }
            appliedCommand = command
            let name = command.split(separator: ".").last.map(String.init) ?? command
            apply(name)
        }
    }

    private var commandBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(["bold", "italic", "heading", "list", "quote"], id: \.self) { command in
                    Button(command.capitalized) { apply(command == "list" ? "bulletList" : command) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityIdentifier("product-ui.richtext.command.\(command)")
                }
            }
        }
        .accessibilityIdentifier("product-ui.editor-toolbar")
    }

    @ViewBuilder private func blockList(_ document: StructuredDocument) -> some View {
        ForEach(Array(document.blocks.enumerated()), id: \.offset) { _, block in
            blockView(block, document: document)
        }
    }

    @ViewBuilder private func blockView(_ block: JSONValue, document: StructuredDocument) -> some View {
        let id = document.blockID(block)
        let type = document.blockType(block)
        if StructuredDocument.editableTypes.contains(type) {
            VStack(alignment: .leading, spacing: 4) {
                Text(type.replacingOccurrences(of: "-", with: " ").capitalized)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                BlockTextView(
                    text: document.visibleText(block),
                    selection: selection,
                    identifier: "product-ui.block.\(id)",
                    font: type == "heading" ? .preferredFont(forTextStyle: .title2) : .preferredFont(forTextStyle: .body),
                    onChange: { updated, range in
                        focusedID = id
                        selection = range
                        commit(document.replacingText(updated, blockID: id))
                    },
                    onSelection: { range in
                        focusedID = id
                        selection = range
                    },
                    onReturn: { range in
                        let split = document.splitting(blockID: id, at: range.location)
                        focusedID = split.1
                        selection = NSRange(location: 0, length: 0)
                        commit(split.0)
                    }
                )
                .frame(minHeight: 44)
            }
            .padding(8)
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Label("Unsupported \(type)", systemImage: "square.dashed")
                    .font(.subheadline.weight(.semibold))
                Text(document.visibleText(block).isEmpty ? "This block is preserved and was not converted." : document.visibleText(block))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("product-ui.block.unsupported.\(id)")
        }
    }

    private func load() {
        do {
            document = try StructuredDocument.parse(text)
            loadError = nil
            preservedSource = nil
            if focusedID == nil { focusedID = document?.blocks.first.map { document!.blockID($0) } }
        } catch StructuredDocument.ReadError.tooLarge {
            document = nil
            loadError = "This document is too large to edit here. The original content is unchanged."
            preservedSource = text
        } catch {
            document = nil
            loadError = "This document could not be read. The original content is unchanged."
            preservedSource = text
        }
    }

    private func apply(_ command: String) {
        guard let document, let id = focusedID ?? document.blocks.first.map(document.blockID) else { return }
        let next = document.applying(command: command, id: id, selection: selection)
        guard next != document else { return }
        commit(next)
    }

    private func commit(_ next: StructuredDocument) {
        let encoded = next.serialize()
        guard encoded != text else {
            document = next
            return
        }
        let previous = text
        undoStack.append(previous)
        if undoStack.count > 50 { undoStack.removeFirst(undoStack.count - 50) }
        redoStack.removeAll()
        document = next
        text = encoded
    }

    private func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(text)
        text = previous
        document = try? StructuredDocument.parse(previous)
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(text)
        text = next
        document = try? StructuredDocument.parse(next)
    }
}

struct BlockTextView: UIViewRepresentable {
    var text: String
    var selection: NSRange
    var identifier: String
    var font: UIFont
    var onChange: (String, NSRange) -> Void
    var onSelection: (NSRange) -> Void
    var onReturn: (NSRange) -> Void

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.font = font
        view.adjustsFontForContentSizeCategory = true
        view.backgroundColor = .clear
        view.isScrollEnabled = false
        view.textContainerInset = UIEdgeInsets(top: 6, left: 2, bottom: 6, right: 2)
        view.accessibilityIdentifier = identifier
        view.text = text
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if view.font != font { view.font = font }
        if view.accessibilityIdentifier != identifier { view.accessibilityIdentifier = identifier }
        if view.text != text {
            let range = view.selectedRange
            view.text = text
            if range.location <= (text as NSString).length {
                view.selectedRange = NSRange(location: min(range.location, (text as NSString).length), length: 0)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: BlockTextView
        init(_ parent: BlockTextView) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.onChange(textView.text ?? "", textView.selectedRange)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            parent.onSelection(textView.selectedRange)
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard text == "\n" else { return true }
            parent.onReturn(range)
            return false
        }
    }
}
