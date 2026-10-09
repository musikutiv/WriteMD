import AppKit

/// Parsed blocks -> attributed text (custom attributes only; `Styler.restyle` adds fonts etc.).
enum DocumentBuilder {
    static func paragraph(_ para: Para, block: Block) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let base: [NSAttributedString.Key: Any] = [.wmdBlock: block, .wmdFlags: InlineFlags([]).number]
        if !para.prefix.isEmpty { out.append(NSAttributedString(string: para.prefix, attributes: base)) }
        if para.raw {
            out.append(NSAttributedString(string: para.body.replacingOccurrences(of: "\n", with: "\u{2028}"), attributes: base))
        } else {
            for run in InlineParser.parse(para.body) {
                var attrs: [NSAttributedString.Key: Any] = [.wmdBlock: block, .wmdFlags: run.flags.number]
                if let l = run.link { attrs[.link] = l }
                out.append(NSAttributedString(string: run.text, attributes: attrs))
            }
        }
        return out
    }

    static func build(_ doc: ParsedDocument) -> NSAttributedString {
        let out = NSMutableAttributedString()
        var first = true
        var prevBlock: Block?
        for pb in doc.blocks {
            for para in pb.paras {
                if !first {
                    out.append(NSAttributedString(string: "\n", attributes: [.wmdBlock: prevBlock!, .wmdFlags: InlineFlags([]).number]))
                }
                first = false
                out.append(paragraph(para, block: pb.block))
                prevBlock = pb.block
            }
        }
        return out
    }
}
