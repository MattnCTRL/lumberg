import Foundation

/// Turns "meetings + open tasks + the time left today" into a schedule of
/// focus blocks and breaks. Pure: same inputs, same plan.
public enum Planner {
    public static func roundUp(_ date: Date, toMinutes step: Int) -> Date {
        let s = Double(step * 60)
        return Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / s).rounded(.up) * s)
    }

    public static func workWindow(for day: Date, settings: PlannerSettings, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let midnight = calendar.startOfDay(for: day)
        return (midnight.addingTimeInterval(Double(settings.workStart) * 60),
                midnight.addingTimeInterval(Double(settings.workEnd) * 60))
    }

    /// Task order: priority, then manual order, then age.
    public static func queue(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks.filter { !$0.isDone }.sorted {
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.createdAt < $1.createdAt
        }
    }

    /// - Parameters:
    ///   - cyclesDone: focus blocks already finished today, so the long break lands in the right place.
    ///   - notBefore: earliest moment new blocks may start (the end of a running session).
    public static func plan(
        now: Date,
        events: [AgendaEvent],
        tasks: [TaskItem],
        settings: PlannerSettings,
        cyclesDone: Int = 0,
        notBefore: Date? = nil,
        calendar: Calendar = .current
    ) -> DayPlan {
        var plan = DayPlan()
        let window = workWindow(for: now, settings: settings, calendar: calendar)
        let dayStart = calendar.startOfDay(for: now)
        let dayEnd = dayStart.addingTimeInterval(86_400)

        let timed = events
            .filter { !$0.isAllDay && $0.end > dayStart && $0.start < dayEnd && $0.end > $0.start }
            .sorted { $0.start < $1.start }

        var blocks: [PlanBlock] = timed.map {
            PlanBlock(id: "meeting-\($0.id)", kind: .meeting, start: $0.start, end: $0.end,
                      title: $0.title, taskID: nil, event: $0)
        }

        // Tasks that have already used up their estimate wait behind the ones that have not.
        let waiting = queue(tasks).map { (task: $0, left: $0.remainingMinutes) }.filter { $0.left > 0 }
        var pending = waiting.filter { $0.task.spentSeconds < $0.task.estimateMinutes * 60 }
            + waiting.filter { $0.task.spentSeconds >= $0.task.estimateMinutes * 60 }
        plan.demandMinutes = pending.reduce(0) { $0 + $1.left }

        let cursor = max(roundUp(max(now, notBefore ?? now), toMinutes: 5), window.start)
        if cursor < window.end {
            // Busy time, padded so focus stops a little before each meeting.
            let buffer = Double(settings.meetingBufferMinutes) * 60
            var busy: [(start: Date, end: Date)] = []
            for e in timed {
                let s = e.start.addingTimeInterval(-buffer), en = e.end
                if en <= cursor || s >= window.end { continue }
                if let last = busy.last, s <= last.end {
                    busy[busy.count - 1].end = max(last.end, en)
                } else {
                    busy.append((s, en))
                }
            }

            var gaps: [(start: Date, end: Date)] = []
            var t = cursor
            for b in busy {
                if b.start > t { gaps.append((t, min(b.start, window.end))) }
                t = max(t, roundUp(b.end, toMinutes: 5))
            }
            if t < window.end { gaps.append((t, window.end)) }

            plan.freeMinutes = gaps.reduce(0) { $0 + Int($1.end.timeIntervalSince($1.start) / 60) }

            var cycles = cyclesDone
            // Blocks in a row on the project at the head of the queue.
            var run = 0
            let turn = max(settings.blocksPerProject ?? 2, 1)
            let minFocus = max(settings.minFocusMinutes, 5)
            let every = max(settings.cyclesBeforeLongBreak, 1)

            for gap in gaps {
                var at = gap.start
                while !pending.isEmpty {
                    let avail = Int(gap.end.timeIntervalSince(at) / 60)
                    if avail < minFocus { break }
                    let head = pending[0]
                    let length = min(settings.focusMinutes, avail, max(head.left, minFocus))
                    let end = at.addingTimeInterval(Double(length) * 60)
                    blocks.append(PlanBlock(
                        id: "focus-\(head.task.id.uuidString)-\(Int(at.timeIntervalSinceReferenceDate))",
                        kind: .focus, start: at, end: end, title: head.task.title,
                        taskID: head.task.id, event: nil))
                    pending[0].left -= length
                    run += 1
                    if pending[0].left <= 0 {
                        pending.removeFirst()
                        run = 0
                    } else if run >= turn, let mine = head.task.projectID,
                              pending.contains(where: { $0.task.projectID != nil && $0.task.projectID != mine }) {
                        // Take turns: this project has had its run, so the next one gets the floor.
                        pending.append(pending.removeFirst())
                        run = 0
                    }
                    cycles += 1

                    let long = cycles % every == 0
                    let rest = long ? settings.longBreakMinutes : settings.shortBreakMinutes
                    let afterRest = end.addingTimeInterval(Double(rest) * 60)
                    // Only take a break if another focus block still fits after it.
                    guard !pending.isEmpty,
                          Int(gap.end.timeIntervalSince(afterRest) / 60) >= minFocus else { break }
                    blocks.append(PlanBlock(
                        id: "break-\(Int(end.timeIntervalSinceReferenceDate))",
                        kind: long ? .longBreak : .shortBreak, start: end, end: afterRest,
                        title: long ? "Long break" : "Break", taskID: nil, event: nil))
                    at = afterRest
                }
            }
        }

        plan.unscheduled = pending.map { Unscheduled(taskID: $0.task.id, minutes: $0.left) }
        plan.blocks = blocks.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
        return plan
    }
}
