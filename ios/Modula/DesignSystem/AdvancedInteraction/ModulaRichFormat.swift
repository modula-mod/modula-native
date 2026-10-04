import SwiftUI
import UIKit

// MARK: - Comment markup
//
// Comments stay plain text on the server (verbatim, ≤5000 chars). The client understands:
// inline  **bold** _italic_ *italic* ++underline++ ~~strike~~ ==highlight== ||spoiler|| `code`
//         ^sup^ ~sub~ $math$ [text](https://…)
// HTML whitelist  <kbd> <mark> <sub> <sup> <u> <s> <abbr title="…"> <span color="name">
//         <details><summary>…</summary>…</details>
// blocks  # / ## / ### heading, > quote, - bullet, 1. numbered, - [ ] / - [x] checklist,
//         ``` code block ```, --- divider
// Anything else renders as literal text, so older comments are unaffected.

enum MarkupStyle: Hashable {
    case bold, italic, underline, strike, highlight, spoiler, code, sup, sub, math, link, kbd, abbr, color
    case details, summary
    case heading(Int), quote, bullet, numbered, checklist(Bool), divider, codeBlock
}

struct MarkupMarker {
    var range: NSRange
    var replacement: String? = nil   // shown instead of the marker when rendered (e.g. "• ")
}

struct MarkupRun {
    var style: MarkupStyle
    var content: NSRange
    var markers: [MarkupMarker]
    var value: String? = nil         // url, colour name, abbr title
}

enum ModulaMarkup {
    static let colors: [String: Color] = [
        "red": .red, "orange": .orange, "yellow": .yellow, "green": .green, "mint": .mint, "teal": .teal,
        "blue": .blue, "indigo": .indigo, "purple": .purple, "pink": .pink, "gray": .gray,
    ]
    static let colorUI: [String: UIColor] = [
        "red": .systemRed, "orange": .systemOrange, "yellow": .systemYellow, "green": .systemGreen, "mint": .systemMint, "teal": .systemTeal,
        "blue": .systemBlue, "indigo": .systemIndigo, "purple": .systemPurple, "pink": .systemPink, "gray": .systemGray,
    ]

    private static func rx(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p, options: []) }

    private static let inline: [(MarkupStyle, NSRegularExpression, Int, Int)] = [
        // style, regex, open marker length, close marker length
        (.bold, rx(#"\*\*(?=\S)([^\n]+?)\*\*"#), 2, 2),
        (.strike, rx(#"~~(?=\S)([^\n]+?)~~"#), 2, 2),
        (.underline, rx(#"\+\+(?=\S)([^\n]+?)\+\+"#), 2, 2),
        (.highlight, rx(#"==(?=\S)([^\n]+?)=="#), 2, 2),
        (.spoiler, rx(#"\|\|([\s\S]+?)\|\|"#), 2, 2),
        (.italic, rx(#"(?<![\w*])_(?=\S)([^_\n]+?)_(?!\w)"#), 1, 1),
        (.italic, rx(#"(?<![\*\w])\*(?=[^\s*])([^*\n]+?)\*(?![\*\w])"#), 1, 1),
        (.sup, rx(#"\^(?=\S)([^\^\n]+?)\^"#), 1, 1),
        (.sub, rx(#"(?<![~\w])~(?=[^\s~])([^~\n]+?)~(?![~\w])"#), 1, 1),
        (.math, rx(#"(?<![\w$])\$(?=[^\s\d])([^$\n]*?\S)\$(?![\w$])"#), 1, 1),
    ]
    private static let codeRx = rx(#"`([^`\n]+)`"#)
    private static let linkRx = rx(#"\[([^\]\n]+)\]\((https?://[^)\s]+)\)"#)
    private static let tagRx = rx(#"<(kbd|mark|sub|sup|u|s)>([\s\S]+?)</\1>"#)
    private static let abbrRx = rx(#"<abbr title="([^"<>]{0,80})">([^<\n]+?)</abbr>"#)
    private static let spanRx = rx(#"<span color="([a-z]+)">([^<]+?)</span>"#)
    private static let detailsRx = rx(#"<details>\s*<summary>([^<\n]+?)</summary>([\s\S]*?)</details>"#)

    /// Parses `text` into styled runs (UTF-16 ranges into `text`).
    static func parse(_ text: String) -> [MarkupRun] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var runs: [MarkupRun] = []
        var protected: [NSRange] = []   // code spans / code blocks: no inline parsing inside

        // Code blocks.
        var lineStart = 0
        var fenceOpen: NSRange?
        var lines: [NSRange] = []
        while lineStart <= ns.length {
            let lineRange = ns.lineRange(for: NSRange(location: min(lineStart, ns.length), length: 0))
            let content = lineRange.length > 0 && ns.substring(with: lineRange).hasSuffix("\n") ? NSRange(location: lineRange.location, length: lineRange.length - 1) : lineRange
            lines.append(content)
            if lineRange.length == 0 { break }
            lineStart = NSMaxRange(lineRange)
            if lineStart >= ns.length { break }
        }
        var inBlock = Set<Int>()
        for (i, line) in lines.enumerated() {
            let s = ns.substring(with: line)
            if s.hasPrefix("```") {
                if let open = fenceOpen {
                    let body = NSRange(location: NSMaxRange(open) + 1, length: max(line.location - NSMaxRange(open) - 2, 0))
                    runs.append(MarkupRun(style: .codeBlock, content: body, markers: [MarkupMarker(range: NSRange(location: open.location, length: min(open.length + 1, ns.length - open.location))), MarkupMarker(range: NSRange(location: max(line.location - 1, 0), length: min(line.length + 1, ns.length - max(line.location - 1, 0))))]))
                    protected.append(NSRange(location: open.location, length: NSMaxRange(line) - open.location))
                    fenceOpen = nil
                } else {
                    fenceOpen = line
                }
                inBlock.insert(i)
            } else if fenceOpen != nil {
                inBlock.insert(i)
            }
        }

        // Line blocks.
        for (i, line) in lines.enumerated() where !inBlock.contains(i) && line.length > 0 {
            let s = ns.substring(with: line)
            func marker(_ len: Int, _ rep: String?) -> MarkupMarker { MarkupMarker(range: NSRange(location: line.location, length: len), replacement: rep) }
            func body(_ len: Int) -> NSRange { NSRange(location: line.location + len, length: line.length - len) }
            if s == "---" || s == "***" {
                runs.append(MarkupRun(style: .divider, content: NSRange(location: line.location, length: 0), markers: [marker(line.length, "────────────")]))
            } else if let m = s.range(of: #"^#{1,3} "#, options: .regularExpression) {
                let len = s.distance(from: m.lowerBound, to: m.upperBound)
                runs.append(MarkupRun(style: .heading(len - 1), content: body(len), markers: [marker(len, nil)]))
            } else if s.hasPrefix("> ") {
                runs.append(MarkupRun(style: .quote, content: body(2), markers: [marker(2, "┃ ")]))
            } else if s.hasPrefix("- [ ] ") || s.hasPrefix("* [ ] ") {
                runs.append(MarkupRun(style: .checklist(false), content: body(6), markers: [marker(6, "☐ ")]))
            } else if s.hasPrefix("- [x] ") || s.hasPrefix("* [x] ") || s.hasPrefix("- [X] ") {
                runs.append(MarkupRun(style: .checklist(true), content: body(6), markers: [marker(6, "☑ ")]))
            } else if s.hasPrefix("- ") || s.hasPrefix("* ") {
                runs.append(MarkupRun(style: .bullet, content: body(2), markers: [marker(2, "•  ")]))
            } else if let m = s.range(of: #"^\d{1,3}\. "#, options: .regularExpression) {
                let len = s.distance(from: m.lowerBound, to: m.upperBound)
                runs.append(MarkupRun(style: .numbered, content: body(len), markers: []))
            }
        }

        func free(_ r: NSRange) -> Bool { !protected.contains { NSIntersectionRange($0, r).length > 0 } }

        // Inline code first (protects its content).
        for m in codeRx.matches(in: text, range: full) where free(m.range) {
            runs.append(MarkupRun(style: .code, content: m.range(at: 1), markers: [MarkupMarker(range: NSRange(location: m.range.location, length: 1)), MarkupMarker(range: NSRange(location: NSMaxRange(m.range) - 1, length: 1))]))
            protected.append(m.range)
        }
        // Links.
        for m in linkRx.matches(in: text, range: full) where free(m.range) {
            let textRange = m.range(at: 1)
            runs.append(MarkupRun(style: .link, content: textRange, markers: [MarkupMarker(range: NSRange(location: m.range.location, length: 1)), MarkupMarker(range: NSRange(location: NSMaxRange(textRange), length: NSMaxRange(m.range) - NSMaxRange(textRange)))], value: ns.substring(with: m.range(at: 2))))
        }
        // HTML whitelist.
        for m in detailsRx.matches(in: text, range: full) where free(m.range) {
            let summary = m.range(at: 1), bodyR = m.range(at: 2)
            runs.append(MarkupRun(style: .summary, content: summary, markers: [MarkupMarker(range: NSRange(location: m.range.location, length: summary.location - m.range.location), replacement: "▸ ")]))
            runs.append(MarkupRun(style: .details, content: bodyR, markers: [MarkupMarker(range: NSRange(location: NSMaxRange(summary), length: bodyR.location - NSMaxRange(summary)), replacement: "\n"), MarkupMarker(range: NSRange(location: NSMaxRange(bodyR), length: NSMaxRange(m.range) - NSMaxRange(bodyR)))]))
        }
        for m in tagRx.matches(in: text, range: full) where free(m.range) {
            let tag = ns.substring(with: m.range(at: 1)), inner = m.range(at: 2)
            let style: MarkupStyle = switch tag { case "kbd": .kbd; case "mark": .highlight; case "sub": .sub; case "sup": .sup; case "u": .underline; default: .strike }
            runs.append(MarkupRun(style: style, content: inner, markers: [MarkupMarker(range: NSRange(location: m.range.location, length: inner.location - m.range.location)), MarkupMarker(range: NSRange(location: NSMaxRange(inner), length: NSMaxRange(m.range) - NSMaxRange(inner)))]))
        }
        for m in abbrRx.matches(in: text, range: full) where free(m.range) {
            let inner = m.range(at: 2)
            runs.append(MarkupRun(style: .abbr, content: inner, markers: [MarkupMarker(range: NSRange(location: m.range.location, length: inner.location - m.range.location)), MarkupMarker(range: NSRange(location: NSMaxRange(inner), length: NSMaxRange(m.range) - NSMaxRange(inner)))], value: ns.substring(with: m.range(at: 1))))
        }
        for m in spanRx.matches(in: text, range: full) where free(m.range) {
            let name = ns.substring(with: m.range(at: 1)), inner = m.range(at: 2)
            guard colors[name] != nil else { continue }
            runs.append(MarkupRun(style: .color, content: inner, markers: [MarkupMarker(range: NSRange(location: m.range.location, length: inner.location - m.range.location)), MarkupMarker(range: NSRange(location: NSMaxRange(inner), length: NSMaxRange(m.range) - NSMaxRange(inner)))], value: name))
        }
        // Inline delimiters.
        for (style, regex, open, close) in inline {
            for m in regex.matches(in: text, range: full) where free(m.range) {
                let overlapsMarker = runs.contains { run in run.markers.contains { NSIntersectionRange($0.range, m.range).length > 0 && !(NSLocationInRange($0.range.location, m.range(at: 1)) ) && $0.range.length > 0 && NSIntersectionRange($0.range, NSRange(location: m.range.location, length: open)).length > 0 } }
                if overlapsMarker { continue }
                runs.append(MarkupRun(style: style, content: m.range(at: 1), markers: [MarkupMarker(range: NSRange(location: m.range.location, length: open)), MarkupMarker(range: NSRange(location: NSMaxRange(m.range) - close, length: close))]))
            }
        }
        return runs
    }

    // MARK: Render (posted comments)

    /// Rendered comment text: styles applied, markers removed or replaced, @mentions/#tags/URLs linked.
    static func render(_ text: String, revealSpoilers: Bool) -> AttributedString {
        let runs = parse(text)
        var result = PostTextLinks.attributed(text)
        guard !runs.isEmpty else { return result }
        func range(_ r: NSRange) -> Range<AttributedString.Index>? {
            guard r.length > 0, let sr = Range(r, in: text) else { return nil }
            return Range(sr, in: result)
        }
        for run in runs {
            guard let r = range(run.content) else { continue }
            switch run.style {
            case .bold: result[r].inlinePresentationIntent = (result[r].inlinePresentationIntent ?? []).union(.stronglyEmphasized)
            case .italic: result[r].inlinePresentationIntent = (result[r].inlinePresentationIntent ?? []).union(.emphasized)
            case .underline: result[r].underlineStyle = .single
            case .strike: result[r].strikethroughStyle = .single
            case .highlight: result[r].backgroundColor = Color.yellow.opacity(0.4)
            case .code: result[r].inlinePresentationIntent = .code; result[r].backgroundColor = Color.secondary.opacity(0.15)
            case .kbd: result[r].inlinePresentationIntent = .code; result[r].backgroundColor = Color.secondary.opacity(0.22)
            case .sup: result[r].baselineOffset = 6; result[r].font = .caption
            case .sub: result[r].baselineOffset = -3; result[r].font = .caption
            case .math: result[r].font = .system(.body, design: .serif).italic()
            case .abbr: result[r].underlineStyle = Text.LineStyle(pattern: .dot)
            case .color: if let c = colors[run.value ?? ""] { result[r].foregroundColor = c }
            case .link: if let url = URL(string: run.value ?? "") { result[r].link = url; result[r].foregroundColor = .accentColor; result[r].underlineStyle = .single }
            case .spoiler:
                if revealSpoilers { result[r].backgroundColor = Color.secondary.opacity(0.12) }
                else { result[r].foregroundColor = .clear; result[r].backgroundColor = Color.secondary.opacity(0.45); result[r].link = nil }
            case .summary: result[r].inlinePresentationIntent = .stronglyEmphasized
            case .details:
                if !revealSpoilers { result[r].foregroundColor = .clear; result[r].font = .system(size: 1) }
                else { result[r].foregroundColor = .secondary }
            case .heading(let level): result[r].font = level == 1 ? .title3.bold() : (level == 2 ? .headline : .subheadline.bold())
            case .quote: result[r].foregroundColor = .secondary; result[r].inlinePresentationIntent = .emphasized
            case .codeBlock: result[r].inlinePresentationIntent = .code; result[r].backgroundColor = Color.secondary.opacity(0.12)
            case .checklist(let done): if done { result[r].strikethroughStyle = .single; result[r].foregroundColor = .secondary }
            case .bullet, .numbered, .divider: break
            }
        }
        // Markers: remove or replace, back to front.
        var markers = runs.flatMap(\.markers).filter { $0.range.length > 0 }
        markers.sort { $0.range.location > $1.range.location }
        var lastStart = Int.max
        for marker in markers where NSMaxRange(marker.range) <= lastStart {
            guard let sr = Range(marker.range, in: text), let ar = Range(sr, in: result) else { continue }
            if let rep = marker.replacement {
                var piece = AttributedString(rep)
                piece.foregroundColor = .secondary
                result.replaceSubrange(ar, with: piece)
            } else {
                result.removeSubrange(ar)
            }
            lastStart = marker.range.location
        }
        return result
    }

    static func hasHiddenContent(_ text: String) -> Bool {
        parse(text).contains { $0.style == .spoiler || $0.style == .details }
    }

    // MARK: Editor highlighting (live WYSIWYG over the raw markup)

    static func highlight(_ storage: NSTextStorage, baseFont: UIFont, textColor: UIColor = .label) {
        let text = storage.string
        let full = NSRange(location: 0, length: (text as NSString).length)
        storage.beginEditing()
        storage.setAttributes([.font: baseFont, .foregroundColor: textColor], range: full)
        let runs = parse(text)
        func traits(_ r: NSRange, _ t: UIFontDescriptor.SymbolicTraits) {
            storage.enumerateAttribute(.font, in: r) { value, sub, _ in
                let f = (value as? UIFont) ?? baseFont
                if let d = f.fontDescriptor.withSymbolicTraits(f.fontDescriptor.symbolicTraits.union(t)) {
                    storage.addAttribute(.font, value: UIFont(descriptor: d, size: f.pointSize), range: sub)
                }
            }
        }
        let mono = UIFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.92, weight: .regular)
        for run in runs {
            let r = run.content
            guard r.location != NSNotFound, NSMaxRange(r) <= full.length else { continue }
            switch run.style {
            case .bold, .summary: traits(r, .traitBold)
            case .italic, .quote: traits(r, .traitItalic); if run.style == .quote { storage.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: r) }
            case .underline: storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: r)
            case .strike: storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: r)
            case .highlight: storage.addAttribute(.backgroundColor, value: UIColor.systemYellow.withAlphaComponent(0.35), range: r)
            case .spoiler: storage.addAttribute(.backgroundColor, value: UIColor.secondaryLabel.withAlphaComponent(0.28), range: r); storage.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: r)
            case .code, .kbd, .codeBlock:
                storage.addAttribute(.font, value: mono, range: r)
                storage.addAttribute(.backgroundColor, value: UIColor.secondaryLabel.withAlphaComponent(0.14), range: r)
            case .sup: storage.addAttribute(.baselineOffset, value: 5, range: r); storage.addAttribute(.font, value: baseFont.withSize(baseFont.pointSize * 0.72), range: r)
            case .sub: storage.addAttribute(.baselineOffset, value: -3, range: r); storage.addAttribute(.font, value: baseFont.withSize(baseFont.pointSize * 0.72), range: r)
            case .math:
                if let d = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body).withDesign(.serif)?.withSymbolicTraits(.traitItalic) { storage.addAttribute(.font, value: UIFont(descriptor: d, size: baseFont.pointSize), range: r) }
            case .abbr: storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue, range: r)
            case .color: if let c = colorUI[run.value ?? ""] { storage.addAttribute(.foregroundColor, value: c, range: r) }
            case .link:
                storage.addAttribute(.foregroundColor, value: UIColor.tintColor, range: r)
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: r)
            case .details: storage.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: r)
            case .heading(let level):
                let size = baseFont.pointSize * (level == 1 ? 1.3 : (level == 2 ? 1.15 : 1.05))
                storage.addAttribute(.font, value: UIFont.systemFont(ofSize: size, weight: .bold), range: r)
            case .checklist(let done): if done { storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: r) }
            case .bullet, .numbered, .divider: break
            }
            // Markers: very faint and slightly smaller.
            for marker in run.markers where marker.range.length > 0 && NSMaxRange(marker.range) <= full.length {
                storage.addAttribute(.foregroundColor, value: UIColor.tertiaryLabel.withAlphaComponent(0.45), range: marker.range)
                storage.addAttribute(.font, value: baseFont.withSize(baseFont.pointSize * 0.78), range: marker.range)
                storage.removeAttribute(.backgroundColor, range: marker.range)
                storage.removeAttribute(.underlineStyle, range: marker.range)
                storage.removeAttribute(.strikethroughStyle, range: marker.range)
            }
        }
        storage.endEditing()
    }
}

// MARK: - Tools

enum ModulaFormatTool: String, CaseIterable, Identifiable {
    case bold, italic, underline, strike, highlight
    case heading, quote, bullet, numbered, checklist
    case code, codeBlock, sup, math, color
    case mention, hashtag, divider, link
    case kbd, mark, sub, htmlSup, details, abbr
    case clear
    var id: String { rawValue }

    var title: String {
        switch self {
        case .bold: "Bold"; case .italic: "Italic"; case .underline: "Underline"; case .strike: "Strikethrough"; case .highlight: "Highlight"
        case .heading: "Heading"; case .quote: "Quote"; case .bullet: "Bulleted list"; case .numbered: "Numbered list"; case .checklist: "Checklist"
        case .code: "Code"; case .codeBlock: "Code block"; case .sup: "Superscript"; case .math: "Inline math"; case .color: "Text colour"
        case .mention: "Mention"; case .hashtag: "Hashtag"; case .divider: "Divider"; case .link: "Link"
        case .kbd: "Keyboard key"; case .mark: "Mark"; case .sub: "Subscript"; case .htmlSup: "Superscript (HTML)"; case .details: "Collapsible details"; case .abbr: "Abbreviation"
        case .clear: "Clear formatting"
        }
    }

    var systemImage: String {
        switch self {
        case .bold: "bold"; case .italic: "italic"; case .underline: "underline"; case .strike: "strikethrough"; case .highlight: "highlighter"
        case .heading: "textformat.size"; case .quote: "text.quote"; case .bullet: "list.bullet"; case .numbered: "list.number"; case .checklist: "checklist"
        case .code: "chevron.left.forwardslash.chevron.right"; case .codeBlock: "curlybraces.square"; case .sup: "textformat.superscript"; case .math: "function"; case .color: "paintpalette"
        case .mention: "at"; case .hashtag: "number"; case .divider: "minus"; case .link: "link"
        case .kbd: "keyboard"; case .mark: "rectangle.dashed"; case .sub: "textformat.subscript"; case .htmlSup: "textformat.superscript"; case .details: "chevron.right.square"; case .abbr: "character.book.closed"
        case .clear: "eraser"
        }
    }

    static let groups: [(String, [ModulaFormatTool])] = [
        ("Text", [.bold, .italic, .underline, .strike, .highlight]),
        ("Blocks", [.heading, .quote, .bullet, .numbered, .checklist]),
        ("Code", [.code, .codeBlock, .sup, .math, .color]),
        ("Insert", [.mention, .hashtag, .divider, .link]),
        ("HTML", [.kbd, .mark, .sub, .htmlSup, .details, .abbr]),
        ("", [.clear]),
    ]

    var inlineMarkers: (String, String)? {
        switch self {
        case .bold: ("**", "**"); case .italic: ("_", "_"); case .underline: ("++", "++"); case .strike: ("~~", "~~"); case .highlight: ("==", "==")
        case .code: ("`", "`"); case .sup: ("^", "^"); case .math: ("$", "$")
        case .kbd: ("<kbd>", "</kbd>"); case .mark: ("<mark>", "</mark>"); case .sub: ("<sub>", "</sub>"); case .htmlSup: ("<sup>", "</sup>")
        default: nil
        }
    }

    var linePrefix: String? {
        switch self {
        case .heading: "## "; case .quote: "> "; case .bullet: "- "; case .numbered: "1. "; case .checklist: "- [ ] "
        default: nil
        }
    }

    /// Styles that light this tool up in the bar.
    func matches(_ style: MarkupStyle) -> Bool {
        switch (self, style) {
        case (.bold, .bold), (.italic, .italic), (.underline, .underline), (.strike, .strike), (.highlight, .highlight),
             (.quote, .quote), (.bullet, .bullet), (.numbered, .numbered), (.code, .code), (.codeBlock, .codeBlock),
             (.sup, .sup), (.math, .math), (.color, .color), (.link, .link), (.kbd, .kbd), (.sub, .sub), (.abbr, .abbr), (.details, .details), (.details, .summary):
            true
        case (.heading, .heading), (.checklist, .checklist): true
        default: false
        }
    }
}

// MARK: - Editor controller

@MainActor @Observable
final class ModulaRichEditorController {
    @ObservationIgnored weak var textView: UITextView?
    @ObservationIgnored var commit: ((String) -> Void)?
    private(set) var active: Set<ModulaFormatTool> = []

    func refreshActive() {
        guard let tv = textView else { active = []; return }
        let sel = tv.selectedRange
        let runs = ModulaMarkup.parse(tv.text)
        var set = Set<ModulaFormatTool>()
        for run in runs {
            let outer = NSRange(location: run.content.location - (run.markers.first?.range.length ?? 0), length: run.content.length + run.markers.reduce(0) { $0 + $1.range.length })
            let hit = sel.length == 0 ? (NSLocationInRange(sel.location, run.content) || sel.location == NSMaxRange(run.content) && run.content.length >= 0 && NSLocationInRange(sel.location, outer)) : NSIntersectionRange(sel, run.content).length == sel.length
            if hit { for tool in ModulaFormatTool.allCases where tool.matches(run.style) { set.insert(tool) } }
        }
        if set != active { active = set }
    }

    private func replace(_ range: NSRange, with string: String, select: NSRange? = nil) {
        guard let tv = textView, let start = tv.position(from: tv.beginningOfDocument, offset: range.location),
              let end = tv.position(from: start, offset: range.length), let r = tv.textRange(from: start, to: end) else { return }
        tv.replace(r, withText: string)
        if let select { tv.selectedRange = select }
        commit?(tv.text)
        refreshActive()
    }

    func apply(_ tool: ModulaFormatTool, value: String? = nil) {
        guard let tv = textView else { return }
        if !tv.isFirstResponder { tv.becomeFirstResponder() }
        let ns = tv.text as NSString
        let sel = tv.selectedRange
        switch tool {
        case .clear:
            clear(in: sel.length > 0 ? sel : NSRange(location: 0, length: ns.length))
        case .mention, .hashtag:
            let needsSpace = sel.location > 0 && !(ns.substring(with: NSRange(location: sel.location - 1, length: 1)).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            let token = (needsSpace ? " " : "") + (tool == .mention ? "@" : "#")
            replace(sel, with: token, select: NSRange(location: sel.location + (token as NSString).length, length: 0))
        case .divider:
            let lead = sel.location > 0 && ns.substring(with: NSRange(location: sel.location - 1, length: 1)) != "\n" ? "\n" : ""
            let insert = lead + "---\n"
            replace(sel, with: insert, select: NSRange(location: sel.location + (insert as NSString).length, length: 0))
        case .codeBlock:
            let inner = ns.substring(with: sel)
            let lead = sel.location > 0 && ns.substring(with: NSRange(location: sel.location - 1, length: 1)) != "\n" ? "\n" : ""
            let insert = lead + "```\n" + inner + "\n```\n"
            let caret = sel.location + (lead as NSString).length + 4 + (inner as NSString).length
            replace(sel, with: insert, select: NSRange(location: caret, length: 0))
        case .color:
            wrap(sel, open: "<span color=\"\(value ?? "pink")\">", close: "</span>", tool: tool)
        case .details:
            let inner = sel.length > 0 ? ns.substring(with: sel) : ""
            let open = "<details><summary>Summary</summary>"
            let insert = open + inner + "</details>"
            replace(sel, with: insert, select: NSRange(location: sel.location + 18, length: 7))
        case .abbr:
            wrap(sel, open: "<abbr title=\"\(value ?? "meaning")\">", close: "</abbr>", tool: tool)
        default:
            if let prefix = tool.linePrefix { toggleLinePrefix(prefix, tool: tool, sel: sel) }
            else if let (open, close) = tool.inlineMarkers { wrap(sel, open: open, close: close, tool: tool) }
        }
        HapticEngine.shared.play(.selection)
    }

    func insertLink(text: String, url: String) {
        guard let tv = textView else { return }
        let sel = tv.selectedRange
        let label = text.isEmpty ? url : text
        let insert = "[\(label)](\(url))"
        replace(sel, with: insert, select: NSRange(location: sel.location + (insert as NSString).length, length: 0))
    }

    func insertAbbreviation(_ abbr: String, title: String) {
        guard let tv = textView else { return }
        let sel = tv.selectedRange
        let safeTitle = title.replacingOccurrences(of: "\"", with: "'").replacingOccurrences(of: "<", with: "").replacingOccurrences(of: ">", with: "")
        let insert = "<abbr title=\"\(String(safeTitle.prefix(80)))\">\(abbr)</abbr>"
        replace(sel, with: insert, select: NSRange(location: sel.location + (insert as NSString).length, length: 0))
    }

    var selectedText: String {
        guard let tv = textView else { return "" }
        return (tv.text as NSString).substring(with: tv.selectedRange)
    }

    /// Toggles a wrapping style on the selection, or on the typing position.
    private func wrap(_ sel: NSRange, open: String, close: String, tool: ModulaFormatTool) {
        guard let tv = textView else { return }
        let ns = tv.text as NSString
        let o = (open as NSString).length, c = (close as NSString).length
        // Already styled → unwrap (or step out of an empty pair / past the closing marker).
        if let run = ModulaMarkup.parse(tv.text).first(where: { tool.matches($0.style) && (sel.length == 0 ? (NSLocationInRange(sel.location, $0.content) || sel.location == NSMaxRange($0.content)) : NSIntersectionRange(sel, $0.content).length == sel.length) }),
           let first = run.markers.first, let last = run.markers.last, run.markers.count == 2 {
            if sel.length == 0 && run.content.length > 0 {
                // Step out: move caret after the closing marker so typing continues unstyled.
                tv.selectedRange = NSRange(location: NSMaxRange(last.range), length: 0)
                refreshActive()
                return
            }
            let inner = ns.substring(with: run.content)
            let whole = NSRange(location: first.range.location, length: NSMaxRange(last.range) - first.range.location)
            replace(whole, with: inner, select: NSRange(location: first.range.location, length: (inner as NSString).length))
            return
        }
        // Empty pair right at the caret → remove it.
        if sel.length == 0, sel.location >= o, sel.location + c <= ns.length,
           ns.substring(with: NSRange(location: sel.location - o, length: o)) == open, ns.substring(with: NSRange(location: sel.location, length: c)) == close {
            replace(NSRange(location: sel.location - o, length: o + c), with: "", select: NSRange(location: sel.location - o, length: 0))
            return
        }
        let inner = ns.substring(with: sel)
        if sel.length == 0 {
            replace(sel, with: open + close, select: NSRange(location: sel.location + o, length: 0))
        } else {
            replace(sel, with: open + inner + close, select: NSRange(location: sel.location + o, length: sel.length))
        }
    }

    private func toggleLinePrefix(_ prefix: String, tool: ModulaFormatTool, sel: NSRange) {
        guard let tv = textView else { return }
        let ns = tv.text as NSString
        let lineRange = ns.lineRange(for: sel)
        var lines = ns.substring(with: lineRange).components(separatedBy: "\n")
        let trailingNewline = lines.last == "" && lines.count > 1
        if trailingNewline { lines.removeLast() }
        let prefixes = ["# ", "## ", "### ", "> ", "- [ ] ", "- [x] ", "- ", "* "]
        let allHave = lines.allSatisfy { line in tool == .numbered ? line.range(of: #"^\d{1,3}\. "#, options: .regularExpression) != nil : line.hasPrefix(prefix) }
        var number = 1
        let updated = lines.map { line -> String in
            var stripped = line
            if let r = stripped.range(of: #"^\d{1,3}\. "#, options: .regularExpression) { stripped.removeSubrange(r) }
            else if let p = prefixes.first(where: { stripped.hasPrefix($0) }) { stripped.removeFirst(p.count) }
            if allHave { return stripped }
            defer { number += 1 }
            return (tool == .numbered ? "\(number). " : prefix) + stripped
        }
        let joined = updated.joined(separator: "\n") + (trailingNewline ? "\n" : "")
        let delta = (joined as NSString).length - lineRange.length
        replace(lineRange, with: joined, select: NSRange(location: max(lineRange.location, NSMaxRange(sel) + delta), length: 0))
    }

    private func clear(in range: NSRange) {
        guard let tv = textView else { return }
        let runs = ModulaMarkup.parse(tv.text)
        var markers = runs.filter { NSIntersectionRange($0.content, range).length > 0 || NSLocationInRange($0.content.location, range) }.flatMap(\.markers).map(\.range).filter { $0.length > 0 }
        markers.sort { $0.location > $1.location }
        var text = tv.text as NSString
        var lastStart = Int.max
        for m in markers where NSMaxRange(m) <= lastStart {
            text = text.replacingCharacters(in: m, with: "") as NSString
            lastStart = m.location
        }
        replace(NSRange(location: 0, length: (tv.text as NSString).length), with: text as String, select: NSRange(location: min(range.location, text.length), length: 0))
    }
}

// MARK: - Live editor (UITextView)

struct ModulaRichTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var controller: ModulaRichEditorController
    var enabled = true
    var spellCheck = true
    var autocapitalize = true
    var returnSends = false
    var maxLines: CGFloat = 6
    var onReturn: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.backgroundColor = .clear
        tv.font = UIFont.preferredFont(forTextStyle: .body)
        tv.adjustsFontForContentSizeCategory = true
        tv.textContainerInset = UIEdgeInsets(top: 11, left: 0, bottom: 11, right: 0)
        tv.textContainer.lineFragmentPadding = 0
        tv.isScrollEnabled = false
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.text = text
        tv.accessibilityIdentifier = "composer.richfield"
        controller.textView = tv
        controller.commit = { [weak coordinator = context.coordinator] value in coordinator?.push(value) }
        context.coordinator.rehighlight(tv)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.parent = self
        tv.isEditable = enabled
        tv.autocorrectionType = spellCheck ? .default : .no
        tv.spellCheckingType = spellCheck ? .default : .no
        tv.autocapitalizationType = autocapitalize ? .sentences : .none
        tv.returnKeyType = returnSends ? .send : .default
        if tv.text != text {
            tv.text = text
            context.coordinator.rehighlight(tv)
            tv.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        }
        if isFocused && !tv.isFirstResponder && tv.window != nil {
            DispatchQueue.main.async { tv.becomeFirstResponder() }
        } else if !isFocused && tv.isFirstResponder {
            DispatchQueue.main.async { tv.resignFirstResponder() }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 240
        let fitting = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let lineHeight = (uiView.font ?? .preferredFont(forTextStyle: .body)).lineHeight
        let maxHeight = lineHeight * maxLines + 22
        let shouldScroll = fitting.height > maxHeight
        if uiView.isScrollEnabled != shouldScroll { DispatchQueue.main.async { uiView.isScrollEnabled = shouldScroll } }
        return CGSize(width: width, height: max(min(fitting.height, maxHeight), 44))
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ModulaRichTextEditor
        init(_ parent: ModulaRichTextEditor) { self.parent = parent }

        func push(_ value: String) {
            if let tv = parent.controller.textView { rehighlight(tv) }
            if parent.text != value { parent.text = value }
        }

        func rehighlight(_ tv: UITextView) {
            let sel = tv.selectedRange
            let base = UIFont.preferredFont(forTextStyle: .body)
            ModulaMarkup.highlight(tv.textStorage, baseFont: base)
            tv.typingAttributes = [.font: base, .foregroundColor: UIColor.label]
            tv.selectedRange = sel
        }

        func textViewDidChange(_ tv: UITextView) {
            rehighlight(tv)
            if parent.text != tv.text { parent.text = tv.text }
            parent.controller.refreshActive()
            tv.invalidateIntrinsicContentSize()
        }

        func textViewDidChangeSelection(_ tv: UITextView) { parent.controller.refreshActive() }
        func textViewDidBeginEditing(_ tv: UITextView) { if !parent.isFocused { parent.isFocused = true } }
        func textViewDidEndEditing(_ tv: UITextView) { if parent.isFocused { parent.isFocused = false } }

        func textView(_ tv: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\n", parent.returnSends { parent.onReturn(); return false }
            // Continue lists on Return.
            if text == "\n" {
                let ns = tv.text as NSString
                let line = ns.substring(with: ns.lineRange(for: NSRange(location: range.location, length: 0))).trimmingCharacters(in: .newlines)
                for prefix in ["- [ ] ", "- [x] ", "- ", "* ", "> "] where line.hasPrefix(prefix) {
                    if line == prefix.trimmingCharacters(in: .whitespaces) || line == prefix {
                        return true
                    }
                    let next = prefix == "- [x] " ? "- [ ] " : prefix
                    tv.insertText("\n" + next)
                    return false
                }
                if let r = line.range(of: #"^(\d{1,3})\. "#, options: .regularExpression), let n = Int(line[r].dropLast(2)) {
                    if line.count > line.distance(from: r.lowerBound, to: r.upperBound) {
                        tv.insertText("\n\(n + 1). ")
                        return false
                    }
                }
            }
            return true
        }
    }
}

// MARK: - Grouped Liquid Glass formatting bar

struct ModulaRichFormattingBar: View {
    var controller: ModulaRichEditorController
    var onLink: () -> Void
    var onAbbr: () -> Void
    var onTranslate: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(ModulaFormatTool.groups.enumerated()), id: \.offset) { index, group in
                        if index > 0 {
                            Capsule().fill(Color.primary.opacity(0.12)).frame(width: 1, height: 20).padding(.horizontal, 4)
                        }
                        if !group.0.isEmpty && group.0 == "HTML" {
                            Text("HTML").font(.system(size: 9, weight: .heavy, design: .rounded)).foregroundStyle(.secondary).padding(.trailing, 2)
                        }
                        ForEach(group.1) { tool in toolButton(tool) }
                    }
                }
                .padding(.horizontal, 6)
            }
            .scrollClipDisabled(false)
            if let onTranslate {
                Button(action: onTranslate) {
                    Image(systemName: "translate").font(.subheadline.weight(.semibold)).frame(width: 36, height: 34)
                }
                .buttonStyle(.plain)
                .modulaGlass(in: Capsule(), interactive: true)
                .accessibilityLabel("Translate")
                .accessibilityIdentifier("composer.translate")
                .padding(.trailing, 4)
            }
        }
        .frame(height: 42)
        .modulaGlass(in: Capsule(), interactive: false, specular: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("composer.formatting")
    }

    @ViewBuilder
    private func toolButton(_ tool: ModulaFormatTool) -> some View {
        let on = controller.active.contains(tool)
        let label = Image(systemName: tool.systemImage)
            .font(.system(size: 15, weight: on ? .bold : .semibold))
            .foregroundStyle(on ? Color.accentColor : Color.primary)
            .frame(width: 36, height: 32)
            .background { if on { Capsule().fill(Color.accentColor.opacity(0.16)) } }
            .contentShape(Capsule())
        Group {
            if tool == .color {
                Menu {
                    ForEach(["red", "orange", "yellow", "green", "teal", "blue", "purple", "pink", "gray"], id: \.self) { name in
                        Button { controller.apply(.color, value: name) } label: {
                            Label(name.capitalized, systemImage: "circle.fill")
                        }
                        .tint(ModulaMarkup.colors[name])
                    }
                } label: { label }
            } else {
                Button {
                    switch tool {
                    case .link: onLink()
                    case .abbr: onAbbr()
                    default: controller.apply(tool)
                    }
                } label: { label }
            }
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.18), value: on)
        .accessibilityLabel(tool.title)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("composer.format.\(tool.rawValue)")
    }
}

/// Small glass sheet for inserting a link (or abbreviation).
struct ModulaLinkInsertSheet: View {
    enum Mode { case link, abbr }
    var mode: Mode = .link
    var initialText: String
    var onInsert: (_ text: String, _ value: String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var value = ""
    @FocusState private var focus: Int?

    private var valid: Bool {
        switch mode {
        case .link:
            let v = value.trimmingCharacters(in: .whitespaces)
            let url = URL(string: v.contains("://") ? v : "https://" + v)
            return url?.host?.contains(".") == true
        case .abbr: return !label.isEmpty && !value.isEmpty
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(mode == .link ? "Add link" : "Abbreviation").font(.headline)
            VStack(spacing: 10) {
                TextField(mode == .link ? "Text (optional)" : "Abbreviation, e.g. HTML", text: $label)
                    .focused($focus, equals: 0)
                    .padding(.horizontal, 14).frame(height: 44)
                    .modulaGlass(in: Capsule(), interactive: false, specular: true)
                TextField(mode == .link ? "https://example.com" : "Meaning", text: $value)
                    .focused($focus, equals: 1)
                    .keyboardType(mode == .link ? .URL : .default)
                    .textInputAutocapitalization(mode == .link ? .never : .sentences)
                    .autocorrectionDisabled(mode == .link)
                    .padding(.horizontal, 14).frame(height: 44)
                    .modulaGlass(in: Capsule(), interactive: false, specular: true)
            }
            HStack {
                Button("Cancel") { dismiss() }
                    .padding(.horizontal, 16).frame(height: 40)
                    .modulaGlass(in: Capsule())
                Spacer()
                Button(mode == .link ? "Add link" : "Insert") {
                    var v = value.trimmingCharacters(in: .whitespaces)
                    if mode == .link && !v.contains("://") { v = "https://" + v }
                    onInsert(label, v)
                    dismiss()
                }
                .font(.headline)
                .foregroundStyle(valid ? Color.white : Color.secondary)
                .padding(.horizontal, 18).frame(height: 40)
                .modulaGlass(in: Capsule(), tint: valid ? .accentColor : nil, prominent: valid)
                .disabled(!valid)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .presentationDetents([.height(250)])
        .presentationBackground(.clear)
        .onAppear {
            label = initialText
            focus = mode == .link ? 1 : (initialText.isEmpty ? 0 : 1)
        }
    }
}
