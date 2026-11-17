import Foundation

/// Who a task or project is for. The list is yours to set: see `WorkTag.definitions`.
public struct WorkTag: RawRepresentable, Codable, Hashable, Identifiable, Sendable {
    public struct Definition: Codable, Equatable, Sendable {
        public var id: String
        public var label: String
        public var short: String
        /// blue, green, red or amber.
        public var color: String
        /// Extra words that pick this tag in quick-add, after `#`.
        public var aliases: [String]

        public init(id: String, label: String, short: String, color: String = "blue", aliases: [String] = []) {
            self.id = id.lowercased()
            self.label = label
            self.short = short
            self.color = color
            self.aliases = aliases
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let id = try c.decode(String.self, forKey: .id).lowercased()
            self.id = id
            label = try c.decodeIfPresent(String.self, forKey: .label) ?? id.capitalized
            short = try c.decodeIfPresent(String.self, forKey: .short) ?? String(id.prefix(4)).uppercased()
            color = try c.decodeIfPresent(String.self, forKey: .color) ?? "blue"
            aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
        }
    }

    public static let defaults = [
        Definition(id: "work", label: "Work", short: "WORK", color: "blue", aliases: ["w"]),
        Definition(id: "client", label: "Client", short: "CL", color: "green", aliases: ["c"]),
        Definition(id: "personal", label: "Personal", short: "ME", color: "amber", aliases: ["me", "home"]),
    ]

    /// The tags on offer. The app replaces this at launch when a local config file lists its own.
    public static var definitions = defaults

    public static var allCases: [WorkTag] { definitions.map { WorkTag($0.id) } }

    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue.lowercased() }
    public init(_ id: String) { self.init(rawValue: id) }

    public var id: String { rawValue }

    var definition: Definition? { Self.definitions.first { $0.id == rawValue } }

    /// A tag saved earlier but no longer listed still shows, under its own name.
    public var label: String { definition?.label ?? rawValue.capitalized }
    public var short: String { definition?.short ?? String(rawValue.prefix(4)).uppercased() }
    public var colorName: String { definition?.color ?? "blue" }
}

public struct TaskItem: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var estimateMinutes: Int
    public var spentSeconds: Int
    /// 1 = high, 2 = normal, 3 = low.
    public var priority: Int
    public var tag: WorkTag?
    public var isDone: Bool
    public var doneAt: Date?
    public var createdAt: Date
    public var order: Double
    /// The project this task belongs to. Nil for loose tasks, and in data saved before projects existed.
    public var projectID: UUID?
    /// For project tasks: the day (yyyy-MM-dd) it was put on the day's list. A project task is only
    /// scheduled on that day; afterwards it goes back to the project's backlog.
    public var plannedDay: String?
    /// True for a "work on this project" time block made by Plan my day, rather than a real task.
    public var isBlock: Bool?

    public init(
        id: UUID = UUID(), title: String, estimateMinutes: Int = 25, spentSeconds: Int = 0,
        priority: Int = 2, tag: WorkTag? = nil, isDone: Bool = false, doneAt: Date? = nil,
        createdAt: Date = Date(), order: Double = 0, projectID: UUID? = nil,
        plannedDay: String? = nil, isBlock: Bool? = nil
    ) {
        self.projectID = projectID
        self.plannedDay = plannedDay
        self.isBlock = isBlock
        self.id = id
        self.title = title
        self.estimateMinutes = estimateMinutes
        self.spentSeconds = spentSeconds
        self.priority = priority
        self.tag = tag
        self.isDone = isDone
        self.doneAt = doneAt
        self.createdAt = createdAt
        self.order = order
    }

    /// Minutes still to schedule. A task that has used up its estimate but is
    /// not marked done keeps asking for a little more time.
    public var remainingMinutes: Int {
        if isDone { return 0 }
        // A project's block for the day is a budget: once it is spent, the day moves on.
        if isBlock == true { return max(estimateMinutes - spentSeconds / 60, 0) }
        return max(estimateMinutes - spentSeconds / 60, 10)
    }
}

public enum ProjectStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case active, paused, done

    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }
}

/// Standing work for one client. Its tasks are a backlog; Plan my day moves some of them onto today.
public struct Project: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var client: WorkTag?
    /// How much time this project should get in a week.
    public var weeklyTargetMinutes: Int
    /// 1 = high, 2 = normal, 3 = low.
    public var priority: Int
    public var deadline: Date?
    public var status: ProjectStatus
    public var createdAt: Date
    /// Where the work lives on disk, if anywhere. Its git history and Claude Code sessions
    /// are read to record what got done.
    public var folder: String?
    /// SSH host name when the folder is on another Mac; nil for this Mac and plugged-in drives.
    public var host: String?
    /// The file name (without .md) of this project's dossier in the dossier folder.
    public var dossier: String?

    public init(id: UUID = UUID(), name: String, client: WorkTag? = nil, weeklyTargetMinutes: Int = 300,
                priority: Int = 2, deadline: Date? = nil, status: ProjectStatus = .active, createdAt: Date = Date(),
                folder: String? = nil, host: String? = nil, dossier: String? = nil) {
        self.folder = folder
        self.host = host
        self.dossier = dossier
        self.id = id
        self.name = name
        self.client = client
        self.weeklyTargetMinutes = weeklyTargetMinutes
        self.priority = priority
        self.deadline = deadline
        self.status = status
        self.createdAt = createdAt
    }

    /// Has a weekly budget, so it takes part in Plan my day and the quick switch buttons.
    /// A project with none is still tracked: its time, its captured work and its dossier.
    public var isBudgeted: Bool { status == .active && weeklyTargetMinutes > 0 }
}

/// A timed thing on the day that the planner must work around.
public struct AgendaEvent: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    /// Calendar name, or the photographed calendar's name for imported events.
    public var source: String
    public var colorHex: String?
    public var location: String?

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool = false,
                source: String, colorHex: String? = nil, location: String? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.source = source
        self.colorHex = colorHex
        self.location = location
    }
}

public enum BlockKind: String, Codable, Sendable {
    case focus, shortBreak, longBreak, meeting

    public var isBreak: Bool { self == .shortBreak || self == .longBreak }
}

public struct PlanBlock: Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: BlockKind
    public var start: Date
    public var end: Date
    public var title: String
    public var taskID: UUID?
    public var event: AgendaEvent?

    public var minutes: Int { Int((end.timeIntervalSince(start) / 60).rounded()) }
}

public struct PlannerSettings: Codable, Equatable, Sendable {
    /// Minutes after midnight.
    public var workStart: Int = 8 * 60
    public var workEnd: Int = 17 * 60
    public var focusMinutes: Int = 25
    public var shortBreakMinutes: Int = 5
    public var longBreakMinutes: Int = 15
    public var cyclesBeforeLongBreak: Int = 4
    /// The shortest stretch worth starting a focus block in.
    public var minFocusMinutes: Int = 15
    /// Focus must end this long before a meeting starts.
    public var meetingBufferMinutes: Int = 5
    /// Focus blocks in a row on one project before the plan moves to the next. Nil means two.
    public var blocksPerProject: Int?

    public init() {}
}

public struct Unscheduled: Equatable, Sendable {
    public var taskID: UUID
    public var minutes: Int
}

public struct DayPlan: Equatable, Sendable {
    /// Meetings for the whole day plus the focus and break blocks still ahead, sorted by start.
    public var blocks: [PlanBlock] = []
    /// Work that does not fit before the end of the day.
    public var unscheduled: [Unscheduled] = []
    /// Free minutes left today inside work hours, outside meetings.
    public var freeMinutes: Int = 0
    /// Minutes of work the open tasks still need.
    public var demandMinutes: Int = 0

    public init() {}

    public var overMinutes: Int { unscheduled.reduce(0) { $0 + $1.minutes } }
    public var focusBlocks: [PlanBlock] { blocks.filter { $0.kind == .focus } }
}

public struct LoggedSession: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var kind: BlockKind
    public var title: String
    public var taskID: UUID?
    /// Copied from the task when the time is logged, so reports survive the task being deleted.
    public var projectID: UUID?
    public var start: Date
    public var end: Date

    public init(id: UUID = UUID(), kind: BlockKind, title: String, taskID: UUID?, projectID: UUID? = nil,
                start: Date, end: Date) {
        self.projectID = projectID
        self.id = id
        self.kind = kind
        self.title = title
        self.taskID = taskID
        self.start = start
        self.end = end
    }
}

public struct DayLog: Codable, Equatable, Sendable {
    public var focusSeconds: Int = 0
    public var pomodoros: Int = 0
    public var completedTasks: [String] = []
    public var sessions: [LoggedSession] = []

    public init() {}
}
