import Foundation

struct BlocklistSource: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var url: URL
    var isEnabled: Bool
}

extension BlocklistSource {
    static func defaultSources() -> [BlocklistSource] {
        [
            BlocklistSource(id: UUID(), name: "OISD Small", url: URL(string: "https://small.oisd.nl/hosts")!, isEnabled: true),
            BlocklistSource(id: UUID(), name: "Energized Blu", url: URL(string: "https://block.energized.pro/blu/formats/hosts")!, isEnabled: false),
            BlocklistSource(id: UUID(), name: "StevenBlack", url: URL(string: "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts")!, isEnabled: false)
        ]
    }
}
