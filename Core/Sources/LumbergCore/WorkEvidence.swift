import Foundation

public struct WorkCommit: Codable, Equatable, Identifiable, Sendable {
    public var hash: String
    public var date: Date
    public var subject: String
    /// Made while a focus block for the project was running.
    public var inFocus: Bool

    public var id: String { hash }

    public init(hash: String, date: Date, subject: String, inFocus: Bool = false) {
        self.hash = hash
        self.date = date
        self.subject = subject
        self.inFocus = inFocus
    }
}

/// Something typed to Claude Code in the project's folder.
public struct WorkPrompt: Codable, Equatable, Identifiable, Sendable {
    public var date: Date
    public var text: String
    public var inFocus: Bool

    public var id: String { "\(date.timeIntervalSince1970)|\(text.prefix(24))" }

    public init(date: Date, text: String, inFocus: Bool = false) {
        self.date = date
        self.text = text
        self.inFocus = inFocus
    }
}

/// What a project's folder shows was done on one day.
public struct WorkCapture: Codable, Equatable, Identifiable, Sendable {
    public var projectID: UUID
    /// yyyy-MM-dd.
    public var day: String
    public var scannedAt: Date
    public var focusMinutes: Int
    public var commits: [WorkCommit]
    public var prompts: [WorkPrompt]
    /// Files Claude Code wrote or edited, relative to the folder where possible.
    public var editedFiles: [String]
    /// Files with changes not yet committed (or, outside git, modified that day).
    public var changedFiles: [String]
    /// The write-up, once Claude has been asked for one.
    public var summary: String?
    /// Dated session notes found beside the work: the time the session began and its topic.
    public var notes: [WorkPrompt]?
    /// The stretches of the day the folder shows work going on, planned or not.
    public var active: [DateInterval]?

    public var id: String { "\(projectID.uuidString)|\(day)" }

    public init(projectID: UUID, day: String, scannedAt: Date = Date(), focusMinutes: Int = 0,
                commits: [WorkCommit] = [], prompts: [WorkPrompt] = [], editedFiles: [String] = [],
                changedFiles: [String] = [], summary: String? = nil, notes: [WorkPrompt]? = nil,
                active: [DateInterval]? = nil) {
        self.notes = notes
        self.active = active
        self.projectID = projectID
        self.day = day
        self.scannedAt = scannedAt
        self.focusMinutes = focusMinutes
        self.commits = commits
        self.prompts = prompts
        self.editedFiles = editedFiles
        self.changedFiles = changedFiles
        self.summary = summary
    }

    public var isEmpty: Bool {
        commits.isEmpty && prompts.isEmpty && editedFiles.isEmpty && changedFiles.isEmpty && sessionNotes.isEmpty
    }

    public var sessionNotes: [WorkPrompt] { notes ?? [] }

    public var files: [String] {
        var seen = Set<String>()
        return (editedFiles + changedFiles).filter { seen.insert($0).inserted }
    }
}

/// Work found in a folder that no project claims: time nobody budgeted.
public struct StrayWork: Equatable, Identifiable, Sendable {
    /// The SSH host it was found on; nil for this Mac.
    public var host: String?
    public var folder: String
    public var spans: [DateInterval]

    public var id: String { "\(host ?? "")|\(folder)" }
    public var minutes: Int { WorkEvidence.minutes(spans) }
    public var name: String { (folder as NSString).lastPathComponent }

    public init(host: String?, folder: String, spans: [DateInterval]) {
        self.host = host
        self.folder = folder
        self.spans = spans
    }
}

/// Reading the traces work leaves behind: git history and Claude Code transcripts.
public enum WorkEvidence {
    /// One line of a Claude Code transcript that matters here.
    public struct TranscriptEvent: Equatable, Sendable {
        public var date: Date
        public var cwd: String
        public var prompt: String?
        public var editedFiles: [String]
    }

    /// Work finished shortly after a block ends still belongs to it.
    public static let slack: TimeInterval = 10 * 60

    /// Claude Code keeps a folder's transcripts under ~/.claude/projects/<this name>.
    public static func claudeDirName(for folder: String) -> String {
        String(folder.map { $0.isLetter && $0.isASCII || $0.isNumber && $0.isASCII ? $0 : "-" })
    }

    public static func inFocus(_ date: Date, windows: [DateInterval]) -> Bool {
        windows.contains { date >= $0.start && date <= $0.end.addingTimeInterval(slack) }
    }

    /// Activity closer together than this is one stretch of work.
    public static let gap: TimeInterval = 30 * 60

    /// Turns moments of activity into stretches of work. A lone moment counts as five minutes.
    public static func spans(_ dates: [Date], gap: TimeInterval = gap, floor: TimeInterval = 5 * 60) -> [DateInterval] {
        var out: [DateInterval] = []
        for date in dates.sorted() {
            if let last = out.last, date.timeIntervalSince(last.end) <= gap {
                out[out.count - 1] = DateInterval(start: last.start, end: max(last.end, date))
            } else {
                out.append(DateInterval(start: date, duration: 0))
            }
        }
        return out.map { $0.duration < floor ? DateInterval(start: $0.start, duration: floor) : $0 }
    }

    public static func minutes(_ spans: [DateInterval]) -> Int {
        Int((spans.reduce(0.0) { $0 + $1.duration } / 60).rounded())
    }

    /// The parts of the spans that fall outside every window: work done off the plan.
    public static func outside(_ spans: [DateInterval], windows: [DateInterval]) -> [DateInterval] {
        let cuts = windows.sorted { $0.start < $1.start }
        var out: [DateInterval] = []
        for span in spans {
            var start = span.start
            for w in cuts where w.end > start && w.start < span.end {
                if w.start > start { out.append(DateInterval(start: start, end: w.start)) }
                start = max(start, w.end)
            }
            if start < span.end { out.append(DateInterval(start: start, end: span.end)) }
        }
        return out.filter { $0.duration >= 60 }
    }

    /// Parses lines of `<ISO timestamp><tab><folder>`: one per moment of Claude Code activity.
    public static func parseActivity(_ text: String) -> [(date: Date, cwd: String)] {
        text.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2, let date = stamp.date(from: String(parts[0])) ?? plainStamp.date(from: String(parts[0]))
            else { return nil }
            return (date, String(parts[1]))
        }
    }

    public static func isInside(_ path: String, _ folder: String) -> Bool {
        path == folder || path.hasPrefix(folder.hasSuffix("/") ? folder : folder + "/")
    }

    /// Groups activity by the folder it belongs to, leaving out the home folder itself, hidden
    /// folders, and anything inside a folder a project already claims. Subfolders fold into
    /// the outermost folder that was worked in.
    public static func strays(_ activity: [(date: Date, cwd: String)], home: String, known: [String],
                              host: String? = nil) -> [StrayWork] {
        let claimed = known.map { $0 == "~" ? home : $0.hasPrefix("~/") ? home + String($0.dropFirst(1)) : $0 }
        let loose = activity.filter { a in
            a.cwd != home && a.cwd != "/" && !a.cwd.contains("/.") && !claimed.contains { isInside(a.cwd, $0) }
        }
        let folders = Set(loose.map(\.cwd))
        let roots = folders.filter { f in !folders.contains { $0 != f && isInside(f, $0) } }
        return roots.map { root in
            StrayWork(host: host, folder: root, spans: spans(loose.filter { isInside($0.cwd, root) }.map(\.date)))
        }
        .sorted { $0.minutes > $1.minutes }
    }

    /// Parses `git log --format=%h%x1f%ct%x1f%s`.
    public static func parseGitLog(_ text: String, windows: [DateInterval] = []) -> [WorkCommit] {
        text.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\u{1f}", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3, let seconds = TimeInterval(parts[1]) else { return nil }
            let date = Date(timeIntervalSince1970: seconds)
            return WorkCommit(hash: String(parts[0]), date: date, subject: String(parts[2]),
                              inFocus: inFocus(date, windows: windows))
        }
        .sorted { $0.date < $1.date }
    }

    /// A session note named `2026-11-10 1005 - what it was about.md`: when it began and its topic.
    public static func parseNoteName(_ name: String, calendar: Calendar = .current) -> (date: Date, topic: String)? {
        guard name.hasSuffix(".md"), let dash = name.range(of: " - ") else { return nil }
        let digits = name[..<dash.lowerBound].filter(\.isNumber)
        guard digits.count == 12 || digits.count == 8 else { return nil }
        let n = digits.map { Int(String($0)) ?? 0 }
        func num(_ from: Int, _ count: Int) -> Int { n[from..<from + count].reduce(0) { $0 * 10 + $1 } }
        var c = DateComponents()
        c.year = num(0, 4); c.month = num(4, 2); c.day = num(6, 2)
        c.hour = digits.count == 12 ? num(8, 2) : 12
        c.minute = digits.count == 12 ? num(10, 2) : 0
        guard let date = calendar.date(from: c) else { return nil }
        let topic = name[dash.upperBound...].dropLast(3).trimmingCharacters(in: .whitespaces)
        return topic.isEmpty ? nil : (date, topic)
    }

    private static let filler: Set<String> = ["work", "project", "projects", "the", "and", "for", "new", "app", "build"]

    /// The words that identify a project, from its name and its folder's name.
    public static func keywords(_ texts: [String]) -> Set<String> {
        Set(texts.flatMap { $0.lowercased().split { !$0.isLetter && !$0.isNumber } }
            .map(String.init).filter { $0.count >= 3 && !filler.contains($0) })
    }

    /// Whether a note kept in a shared folder is about this project.
    public static func note(_ topic: String, mentions keywords: Set<String>) -> Bool {
        !self.keywords([topic]).isDisjoint(with: keywords)
    }

    /// Parses lines of `<seconds since 1970><tab><path>`.
    public static func parseStamped(_ text: String) -> [(date: Date, path: String)] {
        text.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2, let seconds = TimeInterval(parts[0]) else { return nil }
            return (Date(timeIntervalSince1970: seconds), String(parts[1]))
        }
    }

    /// Parses `git status --porcelain` into paths.
    public static func parseGitStatus(_ text: String) -> [String] {
        text.split(separator: "\n").compactMap { line in
            guard line.count > 3 else { return nil }
            var path = String(line.dropFirst(3))
            if let arrow = path.range(of: " -> ") { path = String(path[arrow.upperBound...]) }
            return path.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
    }

    private static let stamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plainStamp = ISO8601DateFormatter()

    private static let writers: Set<String> = ["Edit", "Write", "MultiEdit", "NotebookEdit"]

    /// Picks out what the person asked for and which files were written. Everything else
    /// in a transcript (tool results, system lines, sub-agents) is ignored.
    public static func parseTranscriptLine(_ line: Data) -> TranscriptEvent? {
        guard let o = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let type = o["type"] as? String, type == "user" || type == "assistant",
              o["isSidechain"] as? Bool != true, o["isMeta"] as? Bool != true,
              let raw = o["timestamp"] as? String,
              let date = stamp.date(from: raw) ?? plainStamp.date(from: raw),
              let message = o["message"] as? [String: Any] else { return nil }
        let cwd = o["cwd"] as? String ?? ""
        let blocks = message["content"] as? [[String: Any]] ?? []

        if type == "assistant" {
            let files = blocks.compactMap { b -> String? in
                guard b["type"] as? String == "tool_use", let name = b["name"] as? String, writers.contains(name),
                      let input = b["input"] as? [String: Any] else { return nil }
                return input["file_path"] as? String ?? input["notebook_path"] as? String
            }
            return files.isEmpty ? nil : TranscriptEvent(date: date, cwd: cwd, prompt: nil, editedFiles: files)
        }

        var text = message["content"] as? String ?? ""
        if text.isEmpty {
            if blocks.contains(where: { $0["type"] as? String == "tool_result" }) { return nil }
            text = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
                .joined(separator: " ")
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Slash commands, hook output and the summary that opens a continued session are not requests.
        guard !text.isEmpty, !text.hasPrefix("<"), !text.hasPrefix("This session is being continued"),
              !text.hasPrefix("[Request interrupted"), !text.hasPrefix("[Image") || text.count > 40 else { return nil }
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        return TranscriptEvent(date: date, cwd: cwd, prompt: String(flat.prefix(280)), editedFiles: [])
    }

    public static func relative(_ path: String, to folder: String) -> String {
        let root = folder.hasSuffix("/") ? folder : folder + "/"
        return path.hasPrefix(root) ? String(path.dropFirst(root.count)) : path
    }

    /// The evidence as plain text: what goes to Claude for a write-up, and what Copy puts on the clipboard.
    public static func digest(_ c: WorkCapture, project: String, time: (Date) -> String) -> String {
        var out = ["\(project), \(c.day)", "Focus time logged: \(Quotes.format(c.focusMinutes))", ""]
        if let s = c.summary, !s.isEmpty {
            out += ["What got done:", s, ""]
        }
        if !c.commits.isEmpty {
            out.append("Commits:")
            out += c.commits.map { "- \(time($0.date)) \($0.subject)\($0.inFocus ? "" : " (outside focus time)")" }
            out.append("")
        }
        if !c.sessionNotes.isEmpty {
            out.append("Session notes:")
            out += c.sessionNotes.map { "- \(time($0.date)) \($0.text)" }
            out.append("")
        }
        if !c.prompts.isEmpty {
            out.append("Asked of Claude Code:")
            out += c.prompts.map { "- \(time($0.date)) \($0.text)\($0.inFocus ? "" : " (outside focus time)")" }
            out.append("")
        }
        let files = c.files
        if !files.isEmpty {
            out.append("Files touched:")
            out += files.prefix(40).map { "- \($0)" }
            if files.count > 40 { out.append("- and \(files.count - 40) more") }
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
