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
    private static let supportedMarks: Set<String> = ["bold", "italic", "code", "strikethrough"]

    var schemaVersion: String
    var blocks: [JSONValue]
    /// Preserve fields added by a newer document producer when this host edits known blocks.
    var extraFields: [String: JSONValue] = [:]

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
        if (trimmed.hasPrefix("{") || trimmed.hasPrefix("["))
            && (trimmed.contains("\"blocks\"") || trimmed.contains("\"schemaVersion\"")) {
            guard let data = trimmed.data(using: .utf8),
                  let value = try? JSONDecoder().decode(JSONValue.self, from: data),
                  value["blocks"] != nil, value["schemaVersion"] != nil else { throw ReadError.unreadable }
            guard value["schemaVersion"]?.string == schema else { throw ReadError.unreadable }
            let blocks = value["blocks"]?.array ?? []
            guard blocks.count <= maxBlocks else { throw ReadError.tooLarge }
            guard blocks.allSatisfy({ $0["id"]?.string?.isEmpty == false && $0["type"]?.string?.isEmpty == false }) else {
                throw ReadError.unreadable
            }
            guard case .object(var fields) = value else { throw ReadError.unreadable }
            fields.removeValue(forKey: "schemaVersion")
            fields.removeValue(forKey: "blocks")
            return StructuredDocument(schemaVersion: schema, blocks: blocks, extraFields: fields)
        }
        let parts = trimmed.components(separatedBy: "\n\n")
        let blocks = parts.enumerated().map { index, text in paragraph(id: "block-\(index + 1)", text: text) }
        return StructuredDocument(schemaVersion: schema, blocks: blocks.isEmpty ? [paragraph(id: "block-1", text: "")] : blocks)
    }

    func serialize() -> String {
        var fields = extraFields
        fields["blocks"] = .array(blocks)
        fields["schemaVersion"] = .string(schemaVersion)
        let payload = JSONValue.object(fields)
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

    func canEdit(_ block: JSONValue) -> Bool {
        guard Self.editableTypes.contains(blockType(block)) else { return false }
        if ["bullet-list", "numbered-list", "checklist"].contains(blockType(block)) {
            guard let items = block["items"]?.array,
                  items.allSatisfy({ $0.string != nil }),
                  block["inlines"] == nil else { return false }
        }
        guard let inlines = block["inlines"]?.array else { return true }
        return inlines.allSatisfy { inline in
            guard case .object(let fields) = inline,
                  fields.keys.allSatisfy({ $0 == "text" || $0 == "marks" }),
                  fields["text"]?.string != nil else { return false }
            return (fields["marks"]?.array ?? []).allSatisfy { mark in
                guard case .object(let values) = mark,
                      values.keys.allSatisfy({ $0 == "type" }),
                      let type = values["type"]?.string else { return false }
                return Self.supportedMarks.contains(type)
            }
        }
    }

    func attributedText(_ block: JSONValue, font: UIFont) -> NSAttributedString? {
        guard let inlines = block["inlines"]?.array, canEdit(block) else { return nil }
        let output = NSMutableAttributedString(string: "")
        for inline in inlines {
            let marks = Set((inline["marks"]?.array ?? []).compactMap { $0["type"]?.string })
            var traits: UIFontDescriptor.SymbolicTraits = []
            if marks.contains("bold") { traits.insert(.traitBold) }
            if marks.contains("italic") { traits.insert(.traitItalic) }
            let face = marks.contains("code") ? UIFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
                : font.fontDescriptor.withSymbolicTraits(traits).map { UIFont(descriptor: $0, size: font.pointSize) } ?? font
            var attributes: [NSAttributedString.Key: Any] = [.font: face]
            if marks.contains("strikethrough") { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            output.append(NSAttributedString(string: inline["text"]?.string ?? "", attributes: attributes))
        }
        return output
    }

    func plainText() -> String {
        blocks.map { block in
            blockType(block) == "divider" ? "" : visibleText(block)
        }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Read-only summary for record lists and search. Never returns the JSON envelope.
    static func excerpt(from value: JSONValue?, limit: Int = 240) -> String {
        guard let value else { return "" }
        let raw: String
        switch value {
        case .string(let text): raw = text
        case .object:
            guard value["blocks"] != nil, value["schemaVersion"] != nil else { return "" }
            guard JSONSerialization.isValidJSONObject(value.foundation),
                  let data = try? JSONSerialization.data(withJSONObject: value.foundation),
                  let text = String(data: data, encoding: .utf8) else { return "" }
            raw = text
        default: return ""
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let output: String
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            if let parsed = try? parse(trimmed) {
                output = parsed.plainText()
            } else if trimmed.contains("\"blocks\"") || trimmed.contains("\"schemaVersion\"") {
                // A damaged document envelope is never shown as serialized metadata.
                return ""
            } else {
                // Plain prose may legitimately begin with a brace or bracket.
                output = trimmed
            }
        } else {
            output = trimmed
        }
        let collapsed = output.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    func replacingText(_ newText: String, blockID: String) -> StructuredDocument {
        var copy = self
        copy.blocks = blocks.map { block in
            guard self.blockID(block) == blockID, canEdit(block),
                  case .object(var fields) = block else { return block }
            let type = blockType(block)
            if type == "bullet-list" || type == "numbered-list" || type == "checklist" {
                let items = newText.split(separator: "\n", omittingEmptySubsequences: false).map { JSONValue.string(String($0)) }
                fields["items"] = .array(items)
                if type == "checklist" {
                    let old = fields["checked"]?.array ?? []
                    fields["checked"] = .array((0..<items.count).map { index in index < old.count ? old[index] : .bool(false) })
                }
            } else if let inlines = fields["inlines"]?.array, visibleText(block) != newText {
                fields["inlines"] = .array(Self.replacingInlineText(inlines, with: newText))
                fields.removeValue(forKey: "text")
            } else if fields["inlines"] == nil {
                fields["text"] = .string(newText)
            }
            return .object(fields)
        }
        return copy
    }

    private static func replacingInlineText(_ inlines: [JSONValue], with updated: String) -> [JSONValue] {
        let original = inlines.compactMap { $0["text"]?.string }.joined()
        let oldCharacters = Array(original)
        let newCharacters = Array(updated)
        var prefix = 0
        while prefix < min(oldCharacters.count, newCharacters.count), oldCharacters[prefix] == newCharacters[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < min(oldCharacters.count - prefix, newCharacters.count - prefix),
              oldCharacters[oldCharacters.count - suffix - 1] == newCharacters[newCharacters.count - suffix - 1] { suffix += 1 }
        let leftCount = String(oldCharacters.prefix(prefix)).utf16.count
        let oldRightStart = String(oldCharacters.prefix(oldCharacters.count - suffix)).utf16.count
        let newRightStart = String(newCharacters.prefix(newCharacters.count - suffix)).utf16.count
        let inserted = (updated as NSString).substring(with: NSRange(
            location: leftCount, length: newRightStart - leftCount
        ))
        var before: [JSONValue] = []
        var after: [JSONValue] = []
        var inheritedMarks: JSONValue?
        var offset = 0
        for inline in inlines {
            let text = inline["text"]?.string ?? ""
            let length = (text as NSString).length
            let end = offset + length
            if offset <= leftCount && leftCount <= end { inheritedMarks = inline["marks"] }
            if offset < leftCount {
                let count = min(end, leftCount) - offset
                if count > 0 { before.append(Self.inline((text as NSString).substring(to: count), marks: inline["marks"])) }
            }
            if end > oldRightStart {
                let start = max(0, oldRightStart - offset)
                if start < length { after.append(Self.inline((text as NSString).substring(from: start), marks: inline["marks"])) }
            }
            offset = end
        }
        var result = before
        if !inserted.isEmpty { result.append(Self.inline(inserted, marks: inheritedMarks ?? inlines.first?["marks"])) }
        result.append(contentsOf: after)
        return Self.coalesced(result)
    }

    private static func inline(_ text: String, marks: JSONValue?) -> JSONValue {
        var fields: [String: JSONValue] = ["text": .string(text)]
        if let marks { fields["marks"] = marks }
        return .object(fields)
    }

    private static func coalesced(_ inlines: [JSONValue]) -> [JSONValue] {
        var output: [JSONValue] = []
        for inline in inlines where !(inline["text"]?.string ?? "").isEmpty {
            if let last = output.last, last["marks"] == inline["marks"] {
                output[output.count - 1] = Self.inline(
                    (last["text"]?.string ?? "") + (inline["text"]?.string ?? ""), marks: inline["marks"]
                )
            } else { output.append(inline) }
        }
        return output.isEmpty ? [Self.inline("", marks: nil)] : output
    }

    func applying(command: String, id: String, selection: NSRange) -> StructuredDocument {
        guard let index = blocks.firstIndex(where: { self.blockID($0) == id }) else { return self }
        let block = blocks[index]
        guard canEdit(block) else { return self }
        let source = visibleText(block)
        var copy = self
        switch command {
        case "heading":
            if case .object(var fields) = block {
                fields["type"] = .string("heading")
                fields["level"] = .number(2)
                copy.blocks[index] = .object(fields)
            }
        case "quote":
            if case .object(var fields) = block {
                fields["type"] = .string("quote")
                fields.removeValue(forKey: "level")
                copy.blocks[index] = .object(fields)
            }
        case "code":
            if case .object(var fields) = block {
                fields["type"] = .string("code")
                fields.removeValue(forKey: "level")
                copy.blocks[index] = .object(fields)
            }
        case "bulletList", "list":
            if block["inlines"] != nil { return self }
            copy.blocks[index] = Self.list(id: id, type: "bullet-list", items: source.isEmpty ? [""] : source.components(separatedBy: "\n"))
        case "numberedList":
            if block["inlines"] != nil { return self }
            copy.blocks[index] = Self.list(id: id, type: "numbered-list", items: source.isEmpty ? [""] : source.components(separatedBy: "\n"))
        case "bold", "italic", "strikethrough":
            copy.blocks[index] = Self.addingMark(command, to: block, selection: selection)
        default:
            return self
        }
        return copy
    }

    private static func addingMark(_ mark: String, to block: JSONValue, selection: NSRange) -> JSONValue {
        guard case .object(var fields) = block else { return block }
        let inlines = fields["inlines"]?.array ?? [Self.inline(fields["text"]?.string ?? "", marks: nil)]
        let total = inlines.reduce(0) { $0 + (($1["text"]?.string ?? "") as NSString).length }
        let start = selection.length == 0 ? 0 : min(max(0, selection.location), total)
        let end = selection.length == 0 ? total : min(total, start + max(0, selection.length))
        var offset = 0
        var output: [JSONValue] = []
        for inline in inlines {
            let text = inline["text"]?.string ?? ""
            let ns = text as NSString
            let runEnd = offset + ns.length
            let markedStart = max(offset, start)
            let markedEnd = min(runEnd, end)
            if markedStart >= markedEnd {
                output.append(inline)
                offset = runEnd
                continue
            }
            if offset < markedStart {
                output.append(Self.inline(ns.substring(to: markedStart - offset), marks: inline["marks"]))
            }
            if markedStart < markedEnd {
                var marks = inline["marks"]?.array ?? []
                if !marks.contains(where: { $0["type"]?.string == mark }) {
                    marks.append(.object(["type": .string(mark)]))
                }
                output.append(Self.inline(ns.substring(with: NSRange(location: markedStart - offset, length: markedEnd - markedStart)), marks: .array(marks)))
            }
            if markedEnd < runEnd {
                output.append(Self.inline(ns.substring(from: max(0, markedEnd - offset)), marks: inline["marks"]))
            }
            offset = runEnd
        }
        fields["inlines"] = .array(Self.coalesced(output))
        fields.removeValue(forKey: "text")
        return .object(fields)
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
        if let inlines = blocks[index]["inlines"]?.array, canEdit(blocks[index]),
           case .object(var firstFields) = blocks[index] {
            var before: [JSONValue] = []
            var after: [JSONValue] = []
            var offset = 0
            for inline in inlines {
                let run = (inline["text"]?.string ?? "") as NSString
                let split = min(max(0, location - offset), run.length)
                if split > 0 { before.append(Self.inline(run.substring(to: split), marks: inline["marks"])) }
                if split < run.length { after.append(Self.inline(run.substring(from: split), marks: inline["marks"])) }
                offset += run.length
            }
            let newID = Self.freshID(existing: blocks)
            firstFields["inlines"] = .array(Self.coalesced(before))
            firstFields.removeValue(forKey: "text")
            var copy = self
            copy.blocks[index] = .object(firstFields)
            copy.blocks.insert(.object([
                "id": .string(newID), "type": .string("paragraph"),
                "inlines": .array(Self.coalesced(after)),
            ]), at: index + 1)
            return (copy, newID)
        }
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
    var focusedPresentation = false
    var placeholder = "Start writing"
    @State private var document: StructuredDocument?
    @State private var loadError: String?
    @State private var preservedSource: String?
    @State private var undoStack: [String] = []
    @State private var redoStack: [String] = []
    @State private var focusedID: String?
    @State private var pendingFocusID: String?
    @State private var selection = NSRange(location: 0, length: 0)
    @State private var appliedCommand: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !focusedPresentation {
                HStack {
                    Text("Document").font(.subheadline.weight(.semibold))
                    Spacer()
                    undoRedo
                }
                commandBar
            }
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
            if focusedPresentation {
                commandBar
                HStack { Spacer(); undoRedo }
            }
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

    private var undoRedo: some View {
        HStack {
            Button("Undo") { undo() }.disabled(undoStack.isEmpty).accessibilityIdentifier("product-ui.richtext.undo")
            Button("Redo") { redo() }.disabled(redoStack.isEmpty).accessibilityIdentifier("product-ui.richtext.redo")
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
        if document.canEdit(block) {
            VStack(alignment: .leading, spacing: 4) {
                if !focusedPresentation || type != "paragraph" {
                    Text(type.replacingOccurrences(of: "-", with: " ").capitalized)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                ZStack(alignment: .topLeading) {
                    BlockTextView(
                    text: document.visibleText(block),
                    attributedText: document.attributedText(block, font: type == "heading" ? .preferredFont(forTextStyle: .title2) : .preferredFont(forTextStyle: .body)),
                    selection: selection,
                    identifier: "product-ui.block.\(id)",
                    focusRequested: pendingFocusID == id,
                    font: type == "heading" ? .preferredFont(forTextStyle: .title2) : .preferredFont(forTextStyle: .body),
                    onFocused: { pendingFocusID = nil },
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
                        pendingFocusID = split.1
                        selection = NSRange(location: 0, length: 0)
                        commit(split.0)
                    }
                    )
                    .frame(minHeight: 44)
                    if focusedPresentation && type == "paragraph" && document.visibleText(block).isEmpty {
                        Text(placeholder).foregroundStyle(.tertiary)
                            .padding(.leading, 5).padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }
            }
            .padding(focusedPresentation ? 0 : 8)
            .background {
                if !focusedPresentation {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.quaternary.opacity(0.25))
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Label("Unsupported \(type) preserved", systemImage: "square.dashed")
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

/// A read-only native presentation of a verified structured document. It never mutates stored data.
struct StructuredDocumentReader: View {
    let value: JSONValue

    var body: some View {
        let raw: String? = {
            if let string = value.string { return string }
            guard JSONSerialization.isValidJSONObject(value.foundation),
                  let data = try? JSONSerialization.data(withJSONObject: value.foundation) else { return nil }
            return String(data: data, encoding: .utf8)
        }()
        if let raw, let document = try? StructuredDocument.parse(raw) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(document.blocks.enumerated()), id: \.offset) { _, block in
                    blockView(block, document: document)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("product-ui.structured-document")
        } else {
            ContentUnavailableView("Document unavailable", systemImage: "doc.text")
        }
    }

    @ViewBuilder private func blockView(_ block: JSONValue, document: StructuredDocument) -> some View {
        let type = document.blockType(block)
        let content = formattedText(block, document: document)
        switch type {
        case "heading":
            content.font((block["level"]?.int ?? 2) <= 2 ? .title2.weight(.semibold) : .headline)
        case "quote":
            content.font(.body).italic().padding(.leading, 12)
                .overlay(alignment: .leading) { Rectangle().fill(.tint).frame(width: 2) }
        case "code":
            content.font(.system(.body, design: .monospaced)).padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
        case "bullet-list", "numbered-list", "checklist":
            if let items = block["items"]?.array, items.allSatisfy({ $0.string != nil }) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(type == "numbered-list" ? "\(index + 1)." : type == "checklist" ? ((block["checked"]?.array?.indices.contains(index) == true && block["checked"]?.array?[index].bool == true) ? "☑" : "□") : "•")
                                .foregroundStyle(.secondary)
                            Text(item.string ?? "").font(.body)
                        }
                    }
                }
            } else {
                Label("List content is preserved", systemImage: "list.bullet.rectangle")
                    .foregroundStyle(.secondary)
            }
        case "divider": Divider()
        default:
            if !document.visibleText(block).isEmpty {
                content.font(.body)
            } else {
                Label("Content is preserved", systemImage: "doc.text")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formattedText(_ block: JSONValue, document: StructuredDocument) -> Text {
        guard let inlines = block["inlines"]?.array, !inlines.isEmpty else {
            return Text(document.visibleText(block))
        }
        return inlines.reduce(Text("")) { partial, inline in
            var segment = Text(inline["text"]?.string ?? "")
            for mark in inline["marks"]?.array ?? [] {
                switch mark["type"]?.string {
                case "bold": segment = segment.bold()
                case "italic": segment = segment.italic()
                case "code": segment = segment.font(.system(.body, design: .monospaced))
                case "strikethrough": segment = segment.strikethrough()
                default: break
                }
            }
            return partial + segment
        }
    }
}

struct BlockTextView: UIViewRepresentable {
    var text: String
    var attributedText: NSAttributedString?
    var selection: NSRange
    var identifier: String
    var focusRequested: Bool = false
    var font: UIFont
    var onFocused: () -> Void = {}
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
        if let attributedText { view.attributedText = attributedText }
        else { view.text = text }
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if view.font != font { view.font = font }
        if view.accessibilityIdentifier != identifier { view.accessibilityIdentifier = identifier }
        if view.text != text || attributedText != nil && view.attributedText != attributedText {
            if let attributedText { view.attributedText = attributedText }
            else { view.text = text }
            let count = (text as NSString).length
            let location = min(selection.location, count)
            view.selectedRange = NSRange(location: location, length: min(selection.length, count - location))
        }
        if focusRequested {
            DispatchQueue.main.async {
                if !view.isFirstResponder { view.becomeFirstResponder() }
                onFocused()
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
