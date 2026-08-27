import Foundation

enum BlocklistParser {
    static func parseCanonical(_ data: Data, maximumDomains: Int = 200_000) throws -> Set<String> {
        guard let text = String(data: data, encoding: .utf8), text.hasSuffix("\n") else {
            throw BlocklistParserError.invalidBlocklist
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard !lines.isEmpty, lines.count <= maximumDomains else {
            throw BlocklistParserError.invalidBlocklist
        }
        guard lines == lines.sorted(), lines.count == Set(lines).count else {
            throw BlocklistParserError.invalidBlocklist
        }

        var result = Set<String>(minimumCapacity: lines.count)
        for line in lines {
            guard normalize(line) == line else {
                throw BlocklistParserError.invalidBlocklist
            }
            result.insert(line)
        }
        return result
    }

    static func normalize(_ value: String) -> String? {
        DNSDomainMatcher.normalize(value)
    }

    static func matches(domain: String, entries: Set<String>) -> Bool {
        DNSDomainMatcher.matches(domain: domain, entries: entries)
    }
}

enum BlocklistParserError: Error {
    case invalidBlocklist
}
