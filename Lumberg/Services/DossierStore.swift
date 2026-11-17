import Foundation
import LumbergCore

/// The folder of project dossiers: one Markdown file per project, named `<slug>.md`.
/// Lumberg reads them to learn about projects and writes back what it tracks.
enum DossierStore {
    /// `LUMBERG_DOSSIERS` names the folder. Otherwise a redirected `LUMBERG_HOME` keeps its own
    /// (so a demo never touches the real ones), and the real app uses `~/lumberg/dossiers`.
    static let dir: URL = {
        let env = ProcessInfo.processInfo.environment
        if let d = env["LUMBERG_DOSSIERS"], !d.isEmpty {
            return URL(fileURLWithPath: (d as NSString).expandingTildeInPath, isDirectory: true)
        }
        if let home = env["LUMBERG_HOME"], !home.isEmpty {
            return Store.dir.appendingPathComponent("dossiers", isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("lumberg/dossiers", isDirectory: true)
    }()

    static func url(_ slug: String) -> URL { dir.appendingPathComponent(slug + ".md") }

    /// Every dossier in the folder, by slug. Files starting with `_` and README are not dossiers.
    static func all() -> [(slug: String, dossier: Dossier)] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.sorted().compactMap { name in
            guard name.hasSuffix(".md"), !name.hasPrefix("_"), !name.hasPrefix("."), name.lowercased() != "readme.md",
                  let d = read(String(name.dropLast(3))) else { return nil }
            return (String(name.dropLast(3)), d)
        }
    }

    static func read(_ slug: String) -> Dossier? {
        guard let text = try? String(contentsOf: url(slug), encoding: .utf8) else { return nil }
        return Dossier(text: text)
    }

    /// Writes only when the text differs, so an unchanged dossier keeps its modification time.
    @discardableResult
    static func write(_ slug: String, _ dossier: Dossier) -> Bool {
        let text = dossier.text
        if let old = try? String(contentsOf: url(slug), encoding: .utf8), old == text { return false }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try text.write(to: url(slug), atomically: true, encoding: .utf8)
            return true
        } catch {
            NSLog("Lumberg: could not write dossier \(slug): \(error)")
            return false
        }
    }

    /// A slug no other file uses yet.
    static func freeSlug(for name: String, taken: Set<String>) -> String {
        let base = Dossier.slug(name)
        var slug = base
        var n = 2
        while taken.contains(slug) || FileManager.default.fileExists(atPath: url(slug).path) {
            slug = "\(base)-\(n)"
            n += 1
        }
        return slug
    }
}
