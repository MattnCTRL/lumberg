import Foundation
import LumbergCore

struct AppSettings: Codable, Equatable {
    var planner = PlannerSettings()
    var nagIntervalMinutes = 5
    var meetingLeadMinutes = 5
    var soundsOn = true
    var autoStartBreaks = true
    /// nil means "every calendar except birthdays and holidays".
    var enabledCalendarIDs: [String]?
    var model = "claude-opus-5-5"

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        planner = (try? c.decode(PlannerSettings.self, forKey: .planner)) ?? PlannerSettings()
        nagIntervalMinutes = try c.decodeIfPresent(Int.self, forKey: .nagIntervalMinutes) ?? 5
        meetingLeadMinutes = try c.decodeIfPresent(Int.self, forKey: .meetingLeadMinutes) ?? 5
        soundsOn = try c.decodeIfPresent(Bool.self, forKey: .soundsOn) ?? true
        autoStartBreaks = try c.decodeIfPresent(Bool.self, forKey: .autoStartBreaks) ?? true
        enabledCalendarIDs = try c.decodeIfPresent([String].self, forKey: .enabledCalendarIDs)
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? "claude-opus-5-5"
    }
}

/// The running timer. Time is credited per segment, so pause and resume never double-count.
struct Session: Codable, Equatable {
    var kind: BlockKind
    var taskID: UUID?
    var title: String
    var segmentStart: Date
    var endsAt: Date
    var pausedRemaining: Double?
    var total: Double

    var isPaused: Bool { pausedRemaining != nil }

    func remaining(at now: Date) -> Double {
        pausedRemaining ?? max(0, endsAt.timeIntervalSince(now))
    }

    func progress(at now: Date) -> Double {
        total > 0 ? min(1, max(0, 1 - remaining(at: now) / total)) : 0
    }
}

struct Persisted: Codable {
    var tasks: [TaskItem] = []
    var projects: [Project] = []
    var captures: [WorkCapture] = []
    /// Events read from calendar photos.
    var photoEvents: [ImportedEvent] = []
    var settings = AppSettings()
    var log: [String: DayLog] = [:]
    var session: Session?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tasks = try c.decodeIfPresent([TaskItem].self, forKey: .tasks) ?? []
        projects = try c.decodeIfPresent([Project].self, forKey: .projects) ?? []
        captures = try c.decodeIfPresent([WorkCapture].self, forKey: .captures) ?? []
        photoEvents = try c.decodeIfPresent([ImportedEvent].self, forKey: .photoEvents) ?? []
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        log = try c.decodeIfPresent([String: DayLog].self, forKey: .log) ?? [:]
        session = try c.decodeIfPresent(Session.self, forKey: .session)
    }
}

enum Store {
    /// `LUMBERG_HOME` redirects storage, so a demo run never touches real data.
    static let dir: URL = {
        let url: URL
        if let home = ProcessInfo.processInfo.environment["LUMBERG_HOME"], !home.isEmpty {
            url = URL(fileURLWithPath: home, isDirectory: true)
        } else {
            url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Lumberg", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static var file: URL { dir.appendingPathComponent("state.json") }
    static var apiKeyFile: URL { dir.appendingPathComponent("anthropic-key") }
    static var configFile: URL { dir.appendingPathComponent("config.json") }

    static func load() -> Persisted {
        guard let data = try? Data(contentsOf: file) else { return Persisted() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(Persisted.self, from: data)
        } catch {
            // Keep the unreadable file rather than silently overwriting it.
            let backup = dir.appendingPathComponent("state.unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: file, to: backup)
            NSLog("Lumberg: could not read state.json (\(error)); kept a copy at \(backup.path)")
            return Persisted()
        }
    }

    static func save(_ state: Persisted) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(state).write(to: file, options: .atomic)
        } catch {
            NSLog("Lumberg: could not save state: \(error)")
        }
    }

    static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
