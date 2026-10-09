import AppKit

/// Turns one rendered paragraph back into inline Markdown.
/// Delimiters are emitted only where the run attributes change, never around leading/trailing
/// whitespace (which would make them invalid), and plain text that could be read as markup is escaped.
enum InlineSerializer {
    private enum Span: Equatable {
        case link(String), bold, italic, code(String)
    }

    static func markdown(_ s: NSAttributedString) -> String {
        guard s.length > 0 else { return "" }
        let ns = s.string as NSString
        var chars: [Character] = [], fl: [InlineFlags] = [], lk: [String?] = []
        s.enumerateAttributes(in: s.wmdFullRange, options: []) { attrs, r, _ in
            let f = InlineFlags.from(attrs[.wmdFlags])
            var l: String?
            if let v = attrs[.link] as? String { l = v } else if let u = attrs[.link] as? URL { l = u.absoluteString }
            for ch in ns.substring(with: r) { chars.append(ch); fl.append(f); lk.append(l) }
        }
        let n = chars.count

        // Delimiters must hug non-space text: take edge whitespace out of formatted runs.
        func trim(_ has: (Int) -> Bool, same: (Int, Int) -> Bool, clear: (Int) -> Void) {
            var i = 0
            while i < n {
                guard has(i) else { i += 1; continue }
                var j = i + 1
                while j < n, has(j), same(j - 1, j) { j += 1 }
                var a = i, b = j - 1
                while a < j, chars[a].isWhitespace { clear(a); a += 1 }
                while b >= a, chars[b].isWhitespace { clear(b); b -= 1 }
                i = j
            }
        }
        for flag in [InlineFlags.bold, .italic, .code] {
            trim({ fl[$0].contains(flag) }, same: { _, _ in true }, clear: { fl[$0].remove(flag) })
        }
        trim({ lk[$0] != nil }, same: { lk[$0] == lk[$1] }, clear: { lk[$0] = nil })

        func cls(_ i: Int) -> (Bool, Bool, Bool, String?) {
            (fl[i].contains(.bold), fl[i].contains(.italic), fl[i].contains(.code), lk[i])
        }
        var out = ""
        var stack: [Span] = []
        var i = 0
        while i < n {
            var j = i + 1
            let c0 = cls(i)
            while j < n, cls(j) == c0 { j += 1 }

            var desired: [Span] = []
            if let l = c0.3 { desired.append(.link(l)) }
            if c0.0 { desired.append(.bold) }
            if c0.1 { desired.append(.italic) }
            var codePad = false
            if c0.2 {
                var maxRun = 0, run = 0
                for k in i..<j { if chars[k] == "`" { run += 1; maxRun = max(maxRun, run) } else { run = 0 } }
                codePad = chars[i] == "`" || chars[j - 1] == "`"
                desired.append(.code(String(repeating: "`", count: maxRun + 1) + (codePad ? " " : "")))
            }
            var common = 0
            while common < stack.count, common < desired.count, stack[common] == desired[common] { common += 1 }
            while stack.count > common { out += closer(stack.removeLast()) }
            for s in desired[common...] { out += opener(s); stack.append(s) }

            for k in i..<j {
                let ch = chars[k], f = fl[k]
                if ch == "\u{2028}" { out.append("\n"); continue }
                if c0.2 || f.contains(.raw) { out.append(ch); continue }
                if f.contains(.escaped), InlineParser.isASCIIPunct(ch) { out += "\\"; out.append(ch); continue }
                let prev: Character? = k > 0 ? chars[k - 1] : nil
                let next: Character? = k + 1 < n ? chars[k + 1] : nil
                switch ch {
                case "\\":
                    if let nx = next, InlineParser.isASCIIPunct(nx) { out += "\\\\" } else { out += "\\" }
                case "*":
                    let spaced = (prev == nil || prev!.isWhitespace) && (next == nil || next!.isWhitespace)
                    out += spaced ? "*" : "\\*"
                case "_":
                    let intraword = (prev?.isLetter ?? false || prev?.isNumber ?? false)
                        && (next?.isLetter ?? false || next?.isNumber ?? false)
                    let spaced = (prev == nil || prev!.isWhitespace) && (next == nil || next!.isWhitespace)
                    out += (intraword || spaced) ? "_" : "\\_"
                case "`":
                    out += "\\`"
                default:
                    out.append(ch)
                }
            }
            i = j
        }
        while let s = stack.popLast() { out += closer(s) }
        return out
    }

    private static func opener(_ s: Span) -> String {
        switch s {
        case .link: return "["
        case .bold: return "**"
        case .italic: return "*"
        case .code(let d): return d
        }
    }
    private static func closer(_ s: Span) -> String {
        switch s {
        case .link(let d): return "](\(d))"
        case .bold: return "**"
        case .italic: return "*"
        case .code(let d): return d.hasSuffix(" ") ? " " + d.dropLast() : d
        }
    }
}
