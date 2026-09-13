import Foundation

/// Minimal HTML DOM for parsing server-rendered ollama.com markup.
/// Supports quoted/unquoted attributes, boolean attributes, entities,
/// void elements and script/style raw-text sections.
final class HTMLElement {
    let name: String
    let attributes: [String: String]
    private(set) var children: [HTMLElement] = []
    weak var parent: HTMLElement?

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }

    func appendChild(_ child: HTMLElement) {
        child.parent = self
        children.append(child)
    }

    func attribute(_ name: String) -> String? {
        guard attributes.keys.contains(name) else { return nil }
        return attributes[name]
    }

    var hasParent: Bool { parent != nil }

    func descendants(where predicate: (HTMLElement) -> Bool) -> [HTMLElement] {
        var result: [HTMLElement] = []
        if predicate(self) { result.append(self) }
        for child in children {
            result.append(contentsOf: child.descendants(where: predicate))
        }
        return result
    }

    func nearestAncestor(where predicate: (HTMLElement) -> Bool) -> HTMLElement? {
        var node = parent
        while let current = node {
            if predicate(current) { return current }
            node = current.parent
        }
        return nil
    }

    /// The element's next sibling matching the predicate.
    func nextSibling(where predicate: (HTMLElement) -> Bool) -> HTMLElement? {
        guard let parent, let index = parent.children.firstIndex(where: { $0 === self }) else { return nil }
        for sibling in parent.children[(index + 1)...] where predicate(sibling) {
            return sibling
        }
        return nil
    }
}

enum HTMLParser {
    private static let voidElements: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input",
        "link", "meta", "param", "source", "track", "wbr",
    ]

    private static let rawTextElements: Set<String> = ["script", "style"]

    static func parse(_ html: String) -> HTMLElement? {
        var root: HTMLElement?
        var stack: [HTMLElement] = []
        var index = html.startIndex

        func append(_ element: HTMLElement) {
            if let parent = stack.last {
                parent.appendChild(element)
            } else if root == nil {
                root = element
                stack.append(element)
            } else if let last = stack.last {
                // Multiple top-level roots: hang onto the deepest open element.
                last.appendChild(element)
            }
        }

        func close(_ name: String) {
            guard let matchIndex = stack.lastIndex(where: { $0.name == name }) else { return }
            stack.removeSubrange(matchIndex...)
        }

        while index < html.endIndex {
            guard html[index] == "<",
                  html.index(after: index) < html.endIndex
            else { index = html.index(after: index); continue }

            let next = html[html.index(after: index)]

            if html[index...].hasPrefix("<!--") {
                guard let end = html.range(of: "-->", range: index..<html.endIndex)?.upperBound else { return root }
                index = end
                continue
            }

            if next == "/" {
                guard let end = html[index...].firstIndex(of: ">") else { return root }
                let name = String(html[html.index(html.index(after: index), offsetBy: 1)..<end])
                    .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                close(name)
                index = html.index(after: end)
                continue
            }

            guard next.isLetter else {
                index = html.index(after: index)
                continue
            }

            guard let tagEnd = tagEnd(from: index, in: html) else { return root }
            let rawTag = String(html[html.index(after: index)..<tagEnd])
            let (name, attributes) = parseTag(rawTag)
            let selfClosing = rawTag.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("/")

            let element = HTMLElement(name: name, attributes: attributes)
            append(element)

            if rawTextElements.contains(name) {
                if let closeRange = html.range(of: "</\(name)", options: .caseInsensitive, range: tagEnd..<html.endIndex) {
                    index = html.range(of: ">", range: closeRange.lowerBound..<html.endIndex)?.upperBound ?? html.endIndex
                } else {
                    index = html.endIndex
                }
                continue
            }

            if selfClosing || voidElements.contains(name) {
                // Already appended; make sure it is not left on the stack.
                if stack.last === element { stack.removeLast() }
            } else {
                stack.append(element)
            }
            index = html.index(after: tagEnd)
        }
        return root
    }

    private static func tagEnd(from start: String.Index, in html: String) -> String.Index? {
        var i = start
        var quote: Character?
        while i < html.endIndex {
            let char = html[i]
            if let q = quote {
                if char == q { quote = nil }
            } else if char == "\"" || char == "'" {
                quote = char
            } else if char == ">" {
                return i
            }
            i = html.index(after: i)
        }
        return nil
    }

    private static func parseTag(_ raw: String) -> (name: String, attributes: [String: String]) {
        var name = ""
        var attributes: [String: String] = [:]
        var index = raw.startIndex

        while index < raw.endIndex, !raw[index].isWhitespace { index = raw.index(after: index) }
        name = String(raw[raw.startIndex..<index]).lowercased()

        while index < raw.endIndex {
            while index < raw.endIndex, raw[index].isWhitespace { index = raw.index(after: index) }
            guard index < raw.endIndex else { break }

            var attributeName = ""
            while index < raw.endIndex, !raw[index].isWhitespace, raw[index] != "=" {
                attributeName.append(raw[index])
                index = raw.index(after: index)
            }
            while index < raw.endIndex, raw[index].isWhitespace { index = raw.index(after: index) }

            var value = ""
            if index < raw.endIndex, raw[index] == "=" {
                index = raw.index(after: index)
                while index < raw.endIndex, raw[index].isWhitespace { index = raw.index(after: index) }
                if index < raw.endIndex, raw[index] == "\"" || raw[index] == "'" {
                    let quote = raw[index]
                    index = raw.index(after: index)
                    let start = index
                    while index < raw.endIndex, raw[index] != quote { index = raw.index(after: index) }
                    value = String(raw[start..<index])
                    if index < raw.endIndex { index = raw.index(after: index) }
                } else {
                    let start = index
                    while index < raw.endIndex, !raw[index].isWhitespace { index = raw.index(after: index) }
                    value = String(raw[start..<index])
                }
            }

            guard !attributeName.isEmpty else { continue }
            attributes[attributeName.lowercased()] = decodeEntities(value)
        }
        return (name, attributes)
    }

    private static func decodeEntities(_ value: String) -> String {
        guard value.contains("&") else { return value }
        var result = value
        let named: [String: String] = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
            "&apos;": "'", "&#39;": "'", "&nbsp;": " ",
        ]
        for (entity, replacement) in named {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        if result.contains("&#") {
            result = decodeNumericEntities(result)
        }
        return result
    }

    private static func decodeNumericEntities(_ input: String) -> String {
        let chars = Array(input)
        var output = ""
        var i = 0
        while i < chars.count {
            guard chars[i] == "&", i + 2 < chars.count, chars[i + 1] == "#" else {
                output.append(chars[i])
                i += 1
                continue
            }
            var j = i + 2
            var digits = ""
            while j < chars.count, chars[j].isNumber, digits.count < 7 {
                digits.append(chars[j])
                j += 1
            }
            if j < chars.count, chars[j] == ";", let code = Int(digits), let scalar = Unicode.Scalar(code) {
                output.unicodeScalars.append(scalar)
                i = j + 1
            } else {
                output.append(chars[i])
                i += 1
            }
        }
        return output
    }
}