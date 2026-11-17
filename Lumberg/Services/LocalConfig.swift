import Foundation
import LumbergCore

/// Optional `config.json` beside the state file. It holds what is particular to one person:
/// who the work is for, and what the photographed calendar is called and which time zone it shows.
///
///     {
///       "clients": [
///         { "id": "acme", "label": "Acme", "short": "ACME", "color": "green", "aliases": ["ac"] }
///       ],
///       "photoCalendar": { "name": "Acme", "zone": "America/Los_Angeles" }
///     }
///
/// Colours are blue, green, red or amber. Without the file, the built-in tags are used
/// and photo times are read in this Mac's time zone.
enum LocalConfig {
    private struct File: Decodable {
        struct Photo: Decodable {
            var name: String?
            var zone: String?
        }
        var clients: [WorkTag.Definition]?
        var photoCalendar: Photo?
    }

    static func load() {
        guard let data = try? Data(contentsOf: Store.configFile) else { return }
        guard let file = try? JSONDecoder().decode(File.self, from: data) else {
            NSLog("Lumberg: config.json could not be read, so the built-in tags are in use.")
            return
        }
        if let clients = file.clients, !clients.isEmpty { WorkTag.definitions = clients }
        if let name = file.photoCalendar?.name, !name.isEmpty { PhotoParser.name = name }
        if let id = file.photoCalendar?.zone, let zone = TimeZone(identifier: id) { PhotoParser.zone = zone }
    }
}
