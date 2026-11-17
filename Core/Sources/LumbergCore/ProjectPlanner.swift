import Foundation

/// What Plan my day needs to know about one project.
public struct ProjectLoad: Sendable {
    public var project: Project
    /// Focus time already logged on it this week.
    public var loggedMinutes: Int
    /// Open work from it already on today's list.
    public var plannedMinutes: Int
    /// Its open tasks that are not on today's list yet, in the order they should be picked.
    public var candidates: [TaskItem]

    public init(project: Project, loggedMinutes: Int, plannedMinutes: Int, candidates: [TaskItem]) {
        self.project = project
        self.loggedMinutes = loggedMinutes
        self.plannedMinutes = plannedMinutes
        self.candidates = candidates
    }
}

/// A suggested addition to today. Nothing changes until it is accepted.
public struct Proposal: Equatable, Sendable {
    public struct Line: Identifiable, Equatable, Sendable {
        public var id: UUID
        public var projectID: UUID
        /// Nil means a generic "work on this project" block.
        public var taskID: UUID?
        public var title: String
        public var minutes: Int
    }

    public var lines: [Line] = []
    /// Minutes each project was given today.
    public var shares: [UUID: Int] = [:]
    /// Open time the shares had to fit in, after slack.
    public var budgetMinutes: Int = 0

    public init() {}

    public var totalMinutes: Int { lines.reduce(0) { $0 + $1.minutes } }
}

/// Splits today's open time between projects. Pure: same inputs, same proposal.
public enum ProjectPlanner {
    /// Monday to Friday days left in this week, counting today. At least 1, so weekends still plan.
    public static func workdaysLeft(from day: Date, calendar: Calendar = .current) -> Int {
        let weekday = calendar.component(.weekday, from: day) // 1 = Sunday
        return (2...6).contains(weekday) ? 7 - weekday : 1
    }

    static func weight(_ project: Project, today: Date, calendar: Calendar) -> Double {
        var w = project.priority == 1 ? 1.25 : (project.priority == 3 ? 0.75 : 1.0)
        if let deadline = project.deadline {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: today),
                                               to: calendar.startOfDay(for: deadline)).day ?? 99
            if days <= 3 { w *= 1.5 } else if days <= 7 { w *= 1.25 }
        }
        return w
    }

    static func round5(_ minutes: Double) -> Int { Int((minutes / 5).rounded()) * 5 }

    /// - Parameters:
    ///   - freeMinutes: open time today that nothing is planned in yet.
    ///   - slack: the part of that time left unplanned.
    public static func propose(loads: [ProjectLoad], freeMinutes: Int, today: Date,
                               calendar: Calendar = .current, slack: Double = 0.15) -> Proposal {
        var proposal = Proposal()
        proposal.budgetMinutes = max(0, round5(Double(freeMinutes) * (1 - slack)))
        let days = Double(workdaysLeft(from: today, calendar: calendar))

        let active = loads.filter { $0.project.status == .active }.sorted {
            let a = $0.project, b = $1.project
            if a.priority != b.priority { return a.priority < b.priority }
            if a.deadline != b.deadline { return (a.deadline ?? .distantFuture) < (b.deadline ?? .distantFuture) }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }

        // What each project wants today: its remaining weekly target spread over the days left.
        var wants: [(load: ProjectLoad, minutes: Double)] = []
        for load in active {
            let remaining = Double(max(0, load.project.weeklyTargetMinutes - load.loggedMinutes))
            let want = min(remaining, remaining / days * weight(load.project, today: today, calendar: calendar))
                - Double(load.plannedMinutes)
            if want >= 15 { wants.append((load, want)) }
        }

        let total = wants.reduce(0) { $0 + $1.minutes }
        let scale = total > Double(proposal.budgetMinutes) && total > 0 ? Double(proposal.budgetMinutes) / total : 1

        for (load, want) in wants {
            let share = scale < 1 ? Int(want * scale / 5) * 5 : round5(want)
            guard share >= 15 else { continue }
            proposal.shares[load.project.id] = share

            // Take tasks in order while they fit. The first one always goes in, so a project
            // whose next task is bigger than today's share still moves forward.
            var used = 0
            for task in load.candidates {
                let minutes = task.remainingMinutes
                guard used == 0 || used + minutes <= share + 10 else { continue }
                proposal.lines.append(.init(id: UUID(), projectID: load.project.id, taskID: task.id,
                                            title: task.title, minutes: minutes))
                used += minutes
            }
            // A project with no tasks gets its time held as a plain block.
            if load.candidates.isEmpty {
                proposal.lines.append(.init(id: UUID(), projectID: load.project.id, taskID: nil,
                                            title: "Work on \(load.project.name)", minutes: share - used))
            }
        }
        return proposal
    }
}
