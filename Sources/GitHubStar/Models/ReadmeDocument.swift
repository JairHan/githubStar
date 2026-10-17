import Foundation

struct ReadmeDocument: Sendable {
    let markdown: String
    let sourceURL: URL
    let isTruncated: Bool
}

struct ReadmeBlock: Identifiable, Sendable {
    enum Kind: Sendable { case heading(Int), paragraph, code }
    let id: Int
    let kind: Kind
    let text: String

    static func parse(_ markdown: String) -> [ReadmeBlock] {
        var blocks: [ReadmeBlock] = []
        var lines: [String] = []
        var fence: String?
        func flush(_ kind: Kind) {
            guard !lines.isEmpty else { return }
            blocks.append(ReadmeBlock(id: blocks.count, kind: kind, text: lines.joined(separator: "\n")))
            lines = []
        }
        for line in markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let marker = fence {
                if trimmed.hasPrefix(marker) && trimmed.dropFirst(marker.count).allSatisfy({ $0 == marker.first! || $0.isWhitespace }) {
                    flush(.code); fence = nil
                } else { lines.append(line) }
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flush(.paragraph)
                let first = trimmed.first!
                fence = String(trimmed.prefix(while: { $0 == first }))
            } else if trimmed.isEmpty { flush(.paragraph) }
            else {
                let level = trimmed.prefix(while: { $0 == "#" }).count
                if (1...6).contains(level), trimmed.dropFirst(level).first == " " {
                    flush(.paragraph)
                    blocks.append(.init(id: blocks.count, kind: .heading(level), text: String(trimmed.dropFirst(level + 1))))
                } else { lines.append(line) }
            }
        }
        flush(fence == nil ? .paragraph : .code)
        return blocks
    }
}
