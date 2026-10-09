import Foundation

struct InlineRun: Equatable {
    var text: String
    var flags: InlineFlags
    var link: String?
}

/// Small, forgiving inline parser: emphasis, code spans, inline links. Everything it does not
/// understand (images, inline HTML, math, reference links) stays as literal text, flagged `.raw`
/// where the characters would otherwise be mangled on save.
enum InlineParser {
    static func parse(_ source: String) -> [InlineRun] {
        let chars = Array(source)
        var out: [InlineRun] = []
        parse(chars, 0, chars.count, [], nil, &out)
        var merged: [InlineRun] = []
        for r in out where !r.text.isEmpty {
            if var last = merged.last, last.flags == r.flags, last.link == r.link {
                last.text += r.text
                merged[merged.count - 1] = last
            } else {
                merged.append(r)
            }
        }
        return merged
    }

    // MARK: Character classes

    static func isASCIIPunct(_ c: Character) -> Bool {
        guard let a = c.asciiValue else { return false }
        return (a >= 33 && a <= 47) || (a >= 58 && a <= 64) || (a >= 91 && a <= 96) || (a >= 123 && a <= 126)
    }
    private static func isPunct(_ c: Character) -> Bool { isASCIIPunct(c) || c.isPunctuation || c.isSymbol }
    private static func isWS(_ c: Character?) -> Bool { c == nil || c!.isWhitespace }

    private static func canOpen(_ d: Character, _ prev: Character?, _ next: Character?) -> Bool {
        guard let next = next, !next.isWhitespace else { return false }
        let prevWS = isWS(prev)
        let prevPunct = prev.map(isPunct) ?? false
        let leftFlanking = !isPunct(next) || prevWS || prevPunct
        if d == "_" { return leftFlanking && (prevWS || prevPunct) }
        return leftFlanking
    }

    private static func canClose(_ d: Character, _ prev: Character?, _ next: Character?) -> Bool {
        guard let prev = prev, !prev.isWhitespace else { return false }
        let nextWS = isWS(next)
        let nextPunct = next.map(isPunct) ?? false
        let rightFlanking = !isPunct(prev) || nextWS || nextPunct
        if d == "_" { return rightFlanking && (nextWS || nextPunct) }
        return rightFlanking
    }

    // MARK: Scanner

    private static func parse(_ c: [Character], _ lo: Int, _ hi: Int, _ flags: InlineFlags, _ link: String?,
                              _ out: inout [InlineRun]) {
        var buf = ""
        var i = lo
        func flush() {
            if !buf.isEmpty { out.append(InlineRun(text: buf, flags: flags, link: link)); buf = "" }
        }
        func emit(_ text: String, _ extra: InlineFlags) {
            flush()
            out.append(InlineRun(text: text, flags: flags.union(extra), link: link))
        }
        func str(_ a: Int, _ b: Int) -> String { String(c[a..<b]).replacingOccurrences(of: "\n", with: "\u{2028}") }

        while i < hi {
            let ch = c[i]
            switch ch {
            case "\\":
                if i + 1 < hi, isASCIIPunct(c[i + 1]) {
                    emit(String(c[i + 1]), .escaped); i += 2
                } else { buf.append("\\"); i += 1 }

            case "`":
                var n = 0
                while i + n < hi, c[i + n] == "`" { n += 1 }
                var j = i + n, found = -1
                while j < hi {
                    if c[j] == "`" {
                        var m = 0
                        while j + m < hi, c[j + m] == "`" { m += 1 }
                        if m == n { found = j; break }
                        j += m
                    } else { j += 1 }
                }
                if found >= 0 {
                    var content = str(i + n, found)
                    if content.count >= 2, content.first == " ", content.last == " ",
                       content.contains(where: { $0 != " " }) {
                        content = String(content.dropFirst().dropLast())
                    }
                    emit(content, .code)
                    i = found + n
                } else { buf += String(repeating: "`", count: n); i += n }

            case "!":
                if i + 1 < hi, c[i + 1] == "[", let l = parseLink(c, i + 1, hi) {
                    emit(str(i, l.end), .raw); i = l.end
                } else { buf.append("!"); i += 1 }

            case "[":
                if let l = parseLink(c, i, hi) {
                    if l.textEnd == i + 1 { emit(str(i, l.end), .raw) }
                    else {
                        flush()
                        parse(c, i + 1, l.textEnd, flags, l.dest, &out)
                    }
                    i = l.end
                } else { buf.append("["); i += 1 }

            case "<":
                if i + 1 < hi, c[i + 1].isLetter || "/!?".contains(c[i + 1]),
                   let gt = (i + 1..<hi).first(where: { c[$0] == ">" }) {
                    emit(str(i, gt + 1), .raw); i = gt + 1
                } else { buf.append("<"); i += 1 }

            case "$":
                if let end = mathEnd(c, i, hi) { emit(str(i, end), .raw); i = end }
                else { buf.append("$"); i += 1 }

            case "*", "_":
                var n = 0
                while i + n < hi, c[i + n] == ch { n += 1 }
                let prev: Character? = i > lo ? c[i - 1] : nil
                let next: Character? = i + n < hi ? c[i + n] : nil
                var matched = false
                if canOpen(ch, prev, next) {
                    for kk in stride(from: min(n, 3), through: 1, by: -1) {
                        guard let j = findCloser(c, i + n, hi, ch, kk) else { continue }
                        if n - kk > 0 { buf += String(repeating: ch, count: n - kk) }
                        flush()
                        var f = flags
                        if kk >= 2 { f.insert(.bold) }
                        if kk != 2 { f.insert(.italic) }
                        parse(c, i + n, j, f, link, &out)
                        i = j + kk
                        matched = true
                        break
                    }
                }
                if !matched { buf += String(repeating: ch, count: n); i += n }

            case "\n":
                buf.append("\u{2028}"); i += 1

            default:
                buf.append(ch); i += 1
            }
        }
        flush()
    }

    private static func findCloser(_ c: [Character], _ from: Int, _ hi: Int, _ d: Character, _ kk: Int) -> Int? {
        var j = from
        while j < hi {
            let x = c[j]
            if x == "\\" { j += 2; continue }
            if x == "`" {
                var n = 0
                while j + n < hi, c[j + n] == "`" { n += 1 }
                var k = j + n, found = -1
                while k < hi {
                    if c[k] == "`" {
                        var m = 0
                        while k + m < hi, c[k + m] == "`" { m += 1 }
                        if m == n { found = k; break }
                        k += m
                    } else { k += 1 }
                }
                j = found >= 0 ? found + n : j + n
                continue
            }
            if x == d {
                var m = 0
                while j + m < hi, c[j + m] == d { m += 1 }
                let next: Character? = j + m < hi ? c[j + m] : nil
                if m == kk, j > from, canClose(d, c[j - 1], next) { return j }
                j += m
                continue
            }
            j += 1
        }
        return nil
    }

    /// `[text](dest)` starting at `i` (which holds "["). `end` is exclusive.
    private static func parseLink(_ c: [Character], _ i: Int, _ hi: Int) -> (textEnd: Int, dest: String, end: Int)? {
        var j = i + 1, depth = 1
        while j < hi {
            let x = c[j]
            if x == "\\" { j += 2; continue }
            if x == "`" {
                var n = 0
                while j + n < hi, c[j + n] == "`" { n += 1 }
                j += n
                continue
            }
            if x == "[" { depth += 1 }
            else if x == "]" { depth -= 1; if depth == 0 { break } }
            j += 1
        }
        guard j < hi, c[j] == "]", j + 1 < hi, c[j + 1] == "(" else { return nil }
        var k = j + 2, pd = 1, inQuote = false
        while k < hi {
            let x = c[k]
            if x == "\\" { k += 2; continue }
            if x == "\"" { inQuote.toggle() }
            else if !inQuote {
                if x == "(" { pd += 1 }
                else if x == ")" { pd -= 1; if pd == 0 { break } }
            }
            k += 1
        }
        guard k < hi, c[k] == ")" else { return nil }
        return (j, String(c[(j + 2)..<k]), k + 1)
    }

    private static func mathEnd(_ c: [Character], _ i: Int, _ hi: Int) -> Int? {
        if i + 1 < hi, c[i + 1] == "$" {
            var j = i + 2
            while j + 1 < hi { if c[j] == "$" && c[j + 1] == "$" { return j + 2 }; j += 1 }
            return nil
        }
        guard i + 1 < hi, !c[i + 1].isWhitespace else { return nil }
        var j = i + 1
        while j < hi {
            if c[j] == "\\" { j += 2; continue }
            if c[j] == "$" {
                let nextIsDigit = j + 1 < hi && c[j + 1].isNumber
                if !c[j - 1].isWhitespace && !nextIsDigit { return j + 1 }
                return nil
            }
            j += 1
        }
        return nil
    }
}
