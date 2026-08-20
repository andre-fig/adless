import Foundation

enum BlocklistParser {
    private static let labelPattern = try! NSRegularExpression(pattern: #"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$"#)
    private static let reservedNames: Set<String> = [
        "localhost",
        "localhost.localdomain",
        "broadcasthost",
        "ip6-allnodes",
        "ip6-allrouters",
        "ip6-localhost"
    ]

    static func parseCanonical(_ data: Data, maximumDomains: Int = BlocklistConfiguration.maximumDomainCount) throws -> Set<String> {
        guard let text = String(data: data, encoding: .utf8), text.hasSuffix("\n") else {
            throw BlocklistUpdateError.invalidBlocklist
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard !lines.isEmpty, lines.count <= maximumDomains else {
            throw BlocklistUpdateError.invalidBlocklist
        }
        guard lines == lines.sorted(), lines.count == Set(lines).count else {
            throw BlocklistUpdateError.invalidBlocklist
        }

        var result = Set<String>(minimumCapacity: lines.count)
        for line in lines {
            guard normalize(line) == line else {
                throw BlocklistUpdateError.invalidBlocklist
            }
            result.insert(line)
        }
        return result
    }

    static func normalize(_ value: String) -> String? {
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        guard !candidate.isEmpty,
              !candidate.contains("*"),
              !candidate.contains("/"),
              !candidate.contains("|"),
              !candidate.contains("^"),
              !candidate.contains(":") else { return nil }

        // The generator stores IDNs as their ASCII/Punycode form. DNS wire
        // names are likewise ASCII, so reject non-ASCII input instead of
        // applying a lossy display-text transform at lookup time.
        guard candidate.unicodeScalars.allSatisfy({ $0.value < 128 }) else { return nil }
        guard candidate.contains("."),
              candidate.count <= 253,
              !reservedNames.contains(candidate),
              !isIPAddress(candidate) else { return nil }

        let labels = candidate.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard !labels.isEmpty,
              labels.allSatisfy({ label in
                  guard label.count <= 63 else { return false }
                  let range = NSRange(label.startIndex..<label.endIndex, in: label)
                  return labelPattern.firstMatch(in: label, options: [], range: range) != nil
              }) else { return nil }
        return candidate
    }

    static func matches(domain: String, entries: Set<String>) -> Bool {
        guard let normalized = normalize(domain) else { return false }
        return entries.contains(normalized) || entries.contains(where: { normalized.hasSuffix("." + $0) })
    }

    private static func isIPAddress(_ value: String) -> Bool {
        let parts = value.split(separator: ".")
        if parts.count == 4, parts.allSatisfy({ Int($0) != nil }) { return true }
        return value.contains(":")
    }
}
