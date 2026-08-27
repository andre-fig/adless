import Foundation

/// Shared ASCII/Punycode hostname normalization used by blocklist tooling and
/// its iOS validation tests. DNS wire queries carry IDNs as `xn--` labels.
enum DNSDomainMatcher {
    private static let reservedNames: Set<String> = [
        "localhost",
        "localhost.localdomain",
        "broadcasthost",
        "ip6-allnodes",
        "ip6-allrouters",
        "ip6-localhost"
    ]

    static func normalize(_ value: String) -> String? {
        var candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if candidate.hasSuffix(".") {
            candidate.removeLast()
        }

        guard !candidate.isEmpty,
              !candidate.hasSuffix("."),
              !candidate.hasPrefix("."),
              !candidate.contains(where: { character in
                  character == "/" || character == "|" || character == "^" ||
                  character == ":" || character == "@" || character == "?" ||
                  character == "#"
              }),
              let asciiHost = URL(string: "https://\(candidate)")?.host else {
            return nil
        }

        let normalized = asciiHost.lowercased()

        guard !normalized.isEmpty,
              normalized.count <= 253,
              normalized.contains("."),
              !normalized.contains("*"),
              !reservedNames.contains(normalized),
              !isIPv4Address(normalized),
              normalized.unicodeScalars.allSatisfy({ $0.value < 128 }) else {
            return nil
        }

        let labels = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.allSatisfy({ label in
            guard !label.isEmpty, label.count <= 63,
                  let first = label.first, let last = label.last,
                  isASCIIAlphaNumeric(first), isASCIIAlphaNumeric(last) else {
                return false
            }
            return label.allSatisfy { isASCIIAlphaNumeric($0) || $0 == "-" }
        }) else {
            return nil
        }
        return normalized
    }

    static func matches(domain: String, entries: Set<String>) -> Bool {
        guard let normalized = normalize(domain) else { return false }
        let labels = normalized.split(separator: ".")
        for index in labels.indices where entries.contains(labels[index...].joined(separator: ".")) {
            return true
        }
        return false
    }

    private static func isASCIIAlphaNumeric(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first,
              character.unicodeScalars.count == 1 else { return false }
        return (48...57).contains(scalar.value)
            || (65...90).contains(scalar.value)
            || (97...122).contains(scalar.value)
    }

    private static func isIPv4Address(_ value: String) -> Bool {
        let parts = value.split(separator: ".")
        return parts.count == 4 && parts.allSatisfy { part in
            guard let number = Int(part) else { return false }
            return (0...255).contains(number)
        }
    }
}
