import Foundation

/// A project's dossier: a Markdown file that carries a short header Lumberg reads and writes,
/// a block Lumberg keeps up to date, a dated log, and prose that Lumberg leaves exactly as it is.
///
/// The file is the long-lived record. Anything can edit it (a person, Claude Code, Lumberg);
/// Lumberg only ever touches the header keys it owns, the block between the two markers, and
/// the end of the Log section.
public struct Dossier: Equatable, Sendable {
    public struct Field: Equatable, Sendable {
        /// Empty for a header line that is not `key: value` (kept as written).
        public var key: String
        /// The text after the colon, or the whole line when there is no key.
        public var raw: String
    }

    public var fields: [Field] = []
    /// Everything after the header.
    public var body: String = ""

    public static let autoStart = "<!-- lumberg:auto:start -->"
    public static let autoEnd = "<!-- lumberg:auto:end -->"
    /// A dossier with this status is ignored: its project was removed from Lumberg.
    public static let removed = "removed"

    public init() {}

    // MARK: - Reading and writing the file

    public init(text: String) {
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let close = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" })
        else {
            body = text
            return
        }
        for line in lines[1..<close] {
            if let colon = line.firstIndex(of: ":"), !line.hasPrefix(" "), !line.hasPrefix("#"), !line.hasPrefix("-") {
                let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                let raw = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                if !key.isEmpty, !key.contains(" ") {
                    fields.append(Field(key: key, raw: raw))
                    continue
                }
            }
            fields.append(Field(key: "", raw: line))
        }
        body = lines[(close + 1)...].joined(separator: "\n")
    }

    public var text: String {
        guard !fields.isEmpty else { return body }
        var out = ["---"]
        for f in fields {
            out.append(f.key.isEmpty ? f.raw : (f.raw.isEmpty ? "\(f.key):" : "\(f.key): \(f.raw)"))
        }
        out.append("---")
        return out.joined(separator: "\n") + "\n" + body
    }

    /// A header value with any surrounding quotes taken off. Setting nil removes the key.
    public subscript(key: String) -> String? {
        get {
            guard let raw = fields.first(where: { $0.key == key })?.raw else { return nil }
            var v = raw
            if v.count >= 2, let q = v.first, q == "\"" || q == "'", v.last == q {
                v = String(v.dropFirst().dropLast())
                if q == "\"" { v = v.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\") }
            }
            return v.isEmpty ? nil : v
        }
        set {
            guard let value = newValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
                fields.removeAll { $0.key == key }
                return
            }
            // Leave the line alone when it already says this, however it was quoted.
            if self[key] == value { return }
            let raw = Dossier.quoted(value)
            if let i = fields.firstIndex(where: { $0.key == key }) {
                fields[i].raw = raw
            } else {
                fields.append(Field(key: key, raw: raw))
            }
        }
    }

    static func quoted(_ value: String) -> String {
        let plain = value.range(of: #"^[A-Za-z0-9~/._][A-Za-z0-9~/._ @+()&-]*$"#, options: .regularExpression) != nil
        let word = ["true", "false", "yes", "no", "null", "on", "off"].contains(value.lowercased())
        if plain, !word { return value }
        return "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    // MARK: - Header and project

    /// Lowercase letters, digits and dashes, for the file name.
    public static func slug(_ name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        let parts = folded.split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }
        let s = parts.joined(separator: "-")
        return s.isEmpty ? "project" : String(s.prefix(60))
    }

    static func dayFormatter(_ calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    static func hours(_ minutes: Int) -> String {
        if minutes % 60 == 0 { return String(minutes / 60) }
        let h = (Double(minutes) / 60 * 100).rounded() / 100
        return String(h)
    }

    /// True when the header marks this as a dossier Lumberg should follow.
    public var isTracked: Bool {
        self["lumberg"] != nil && self["name"] != nil && self["status"]?.lowercased() != Dossier.removed
    }

    /// Copies what the header says onto a project. Keys that are missing leave the project as it is.
    public func apply(to project: inout Project, calendar: Calendar = .current) {
        if let name = self["name"] { project.name = name }
        if fields.contains(where: { $0.key == "client" }) { project.client = self["client"].flatMap { $0.isEmpty ? nil : WorkTag($0) } }
        if let status = self["status"], let s = ProjectStatus(rawValue: status.lowercased()) { project.status = s }
        if let p = self["priority"].flatMap(Int.init), (1...3).contains(p) { project.priority = p }
        if let h = self["weekly_hours"].flatMap(Double.init), h >= 0 { project.weeklyTargetMinutes = Int((h * 60).rounded()) }
        if fields.contains(where: { $0.key == "deadline" }) {
            let day = self["deadline"].flatMap { Dossier.dayFormatter(calendar).date(from: $0) }
            let same = day.map { d in project.deadline.map { calendar.isDate($0, inSameDayAs: d) } ?? false } ?? (project.deadline == nil)
            // Noon, so the day survives a change of time zone.
            if !same { project.deadline = day.flatMap { calendar.date(bySettingHour: 12, minute: 0, second: 0, of: $0) } }
        }
        if fields.contains(where: { $0.key == "folder" }) { project.folder = self["folder"] }
        if fields.contains(where: { $0.key == "host" }) { project.host = self["host"] }
    }

    /// Writes a project's settings into the header. Returns true when anything changed.
    @discardableResult
    public mutating func take(from project: Project, slug: String, calendar: Calendar = .current) -> Bool {
        let before = fields
        if self["lumberg"] == nil { fields.insert(Field(key: "lumberg", raw: "1"), at: 0) }
        if self["slug"] == nil { self["slug"] = slug }
        self["name"] = project.name
        // An empty key is kept (as `client:`), so a later read knows the value was cleared.
        func put(_ key: String, _ value: String?) {
            if let value, !value.isEmpty { self[key] = value; return }
            if let i = fields.firstIndex(where: { $0.key == key }) { fields[i].raw = "" } else { fields.append(Field(key: key, raw: "")) }
        }
        put("client", project.client?.rawValue)
        self["status"] = project.status.rawValue
        self["priority"] = String(project.priority)
        if self["weekly_hours"].flatMap(Double.init).map({ Int(($0 * 60).rounded()) }) != project.weeklyTargetMinutes {
            self["weekly_hours"] = Dossier.hours(project.weeklyTargetMinutes)
        }
        put("deadline", project.deadline.map { Dossier.dayFormatter(calendar).string(from: $0) })
        put("folder", project.folder)
        put("host", project.host?.trimmingCharacters(in: .whitespaces))
        return fields != before
    }

    // MARK: - Body

    /// The first paragraph under "What it is", for showing in the app.
    public var summary: String? {
        let lines = body.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { $0.lowercased().hasPrefix("## what it is") }) else { return nil }
        var out: [String] = []
        for line in lines[(start + 1)...] {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("#") || t.hasPrefix("<!--") { break }
            if t.isEmpty { if out.isEmpty { continue } else { break } }
            out.append(t)
        }
        return out.isEmpty ? nil : out.joined(separator: " ")
    }

    /// Replaces the block Lumberg owns. Returns true when the body changed.
    @discardableResult
    public mutating func setAuto(_ markdown: String) -> Bool {
        let block = Dossier.autoStart + "\n" + markdown.trimmingCharacters(in: .whitespacesAndNewlines) + "\n" + Dossier.autoEnd
        let before = body
        if let a = body.range(of: Dossier.autoStart), let b = body.range(of: Dossier.autoEnd, range: a.upperBound..<body.endIndex) {
            body.replaceSubrange(a.lowerBound..<b.upperBound, with: block)
        } else if let log = Dossier.heading("log", in: body) {
            body.insert(contentsOf: block + "\n\n", at: log.lowerBound)
        } else {
            body = Dossier.trimmedEnd(body) + "\n\n" + block + "\n"
        }
        return body != before
    }

    /// The text Lumberg last wrote between its markers.
    public var auto: String? {
        guard let a = body.range(of: Dossier.autoStart), let b = body.range(of: Dossier.autoEnd, range: a.upperBound..<body.endIndex)
        else { return nil }
        return String(body[a.upperBound..<b.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func trimmedEnd(_ s: String) -> String {
        var s = s
        while let last = s.last, last.isNewline || last == " " { s.removeLast() }
        return s
    }

    /// The range of a `## title` line, matched without regard to case.
    static func heading(_ title: String, in body: String) -> Range<String.Index>? {
        var index = body.startIndex
        while index < body.endIndex {
            let end = body[index...].firstIndex(of: "\n") ?? body.endIndex
            let line = body[index..<end].trimmingCharacters(in: .whitespaces).lowercased()
            if line == "## " + title { return index..<end }
            index = end < body.endIndex ? body.index(after: end) : end
        }
        return nil
    }

    /// Adds a dated line to the end of the Log section, making the section if it is not there.
    public mutating func appendLog(_ note: String, day: String) {
        let text = note.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let entry = "- \(day): \(text)"
        guard let log = Dossier.heading("log", in: body) else {
            body = Dossier.trimmedEnd(body) + "\n\n## Log\n\n" + entry + "\n"
            return
        }
        // The section runs to the next heading of the same or a higher level, or the end.
        var end = body.endIndex
        var index = log.upperBound
        while index < body.endIndex {
            let lineEnd = body[index...].firstIndex(of: "\n") ?? body.endIndex
            let line = body[index..<lineEnd]
            if index > log.upperBound, line.hasPrefix("## ") || line.hasPrefix("# ") { end = index; break }
            index = lineEnd < body.endIndex ? body.index(after: lineEnd) : lineEnd
        }
        let section = String(body[log.upperBound..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        let rest = String(body[end...])
        let rebuilt = "\n\n" + (section.isEmpty ? entry : section + "\n" + entry) + "\n" + (rest.isEmpty ? "" : "\n")
        body.replaceSubrange(log.upperBound..<end, with: rebuilt)
    }

    // MARK: - New dossiers and the tracked block

    /// A fresh dossier for a project made inside Lumberg.
    public static func template(for project: Project, slug: String, day: String, calendar: Calendar = .current) -> Dossier {
        var d = Dossier()
        d.fields = [Field(key: "lumberg", raw: "1"), Field(key: "slug", raw: slug)]
        d.take(from: project, slug: slug, calendar: calendar)
        d["created"] = day
        d.body = """

        # \(project.name)

        ## What it is

        _Not written yet._

        ## Where it lives

        \(project.folder.map { "- `\($0)`" + (project.host.map { " on \($0)" } ?? "") } ?? "_No folder set._")

        ## Current state

        _Not written yet._

        ## Open and next

        _Nothing recorded._

        ## Log

        - \(day): Project created in Lumberg.

        """
        return d
    }

    /// One day of captured work, as the tracked block shows it.
    public struct TrackedDay: Equatable, Sendable {
        public var day: String
        public var workedMinutes: Int
        public var commits: Int
        public var requests: Int
        public var summary: String?

        public init(day: String, workedMinutes: Int, commits: Int, requests: Int, summary: String? = nil) {
            self.day = day
            self.workedMinutes = workedMinutes
            self.commits = commits
            self.requests = requests
            self.summary = summary
        }
    }

    /// The block Lumberg keeps current. It carries no "written at" time, so it only changes when the facts do.
    public static func tracked(project: Project, weekOf: String, weekMinutes: Int, fourWeekMinutes: Int,
                               lastFocus: String?, openTasks: [String], days: [TrackedDay]) -> String {
        func span(_ m: Int) -> String { m < 60 ? "\(m)m" : (m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m") }
        var out = ["## Tracked by Lumberg", "", "_Lumberg rewrites this block. Edit anything outside it._", ""]
        let target = project.weeklyTargetMinutes > 0 ? "of \(span(project.weeklyTargetMinutes)) budgeted" : "(no weekly budget set)"
        out.append("- Week of \(weekOf): \(span(weekMinutes)) of focus time logged \(target)")
        out.append("- Last four weeks: \(span(fourWeekMinutes)) of focus time logged")
        out.append("- Last focus block: \(lastFocus ?? "none yet")")
        if !openTasks.isEmpty {
            out.append("- Open tasks (\(openTasks.count)):")
            for t in openTasks.prefix(12) { out.append("  - \(t)") }
            if openTasks.count > 12 { out.append("  - and \(openTasks.count - 12) more") }
        }
        let shown = days.filter { $0.workedMinutes > 0 || $0.commits > 0 || $0.requests > 0 }.sorted { $0.day > $1.day }.prefix(14)
        if !shown.isEmpty {
            out += ["", "| Day | Worked | Commits | Requests to Claude | What got done |", "|---|---|---|---|---|"]
            for d in shown {
                let s = (d.summary ?? "").split(whereSeparator: \.isNewline).joined(separator: " ")
                    .replacingOccurrences(of: "|", with: "/")
                out.append("| \(d.day) | \(d.workedMinutes > 0 ? span(d.workedMinutes) : "") | \(d.commits) | \(d.requests) | \(s.count > 240 ? String(s.prefix(240)) + "…" : s) |")
            }
        }
        return out.joined(separator: "\n")
    }
}
