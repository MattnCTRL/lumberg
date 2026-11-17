import Foundation

/// What the boss says. `seed` picks the line so a given moment always reads the same.
public enum Quotes {
    static func pick(_ lines: [String], _ seed: Int) -> String {
        lines[abs(seed) % lines.count]
    }

    public static func start(task: String, seed: Int) -> String {
        pick([
            "Yeahhh, I'm gonna need you to go ahead and start on \(task). Mmmkay?",
            "Hi. What's happening. So if you could just go ahead and get going on \(task), that'd be great.",
            "So, uh, \(task) isn't going to do itself. If you could get on that, that'd be terrific.",
            "I'm gonna have to go ahead and ask you to pick up \(task) now. Thanks a bunch.",
        ], seed)
    }

    public static func idle(seed: Int) -> String {
        pick([
            "Hi. What's happening. Looks like nothing's on the list. Why don't you go ahead and add something.",
            "Yeahhh, we have sort of a problem here. Nothing's scheduled.",
            "If you could go ahead and tell me what you're working on, that'd be great.",
        ], seed)
    }

    public static func focusDone(task: String, seed: Int) -> String {
        pick([
            "Mmmkay, that's time on \(task). Go ahead and take five.",
            "Great. That's one in the books for \(task). Grab a coffee.",
            "Terrific. Step away from \(task) for a few minutes.",
        ], seed)
    }

    public static func breakOver(next: String?, seed: Int) -> String {
        guard let next else {
            return "Break's over. Nothing left on the list, so, uh, that's great."
        }
        return pick([
            "Break's over. I'm gonna need you to go ahead and get back on \(next).",
            "So if you could go ahead and come back now, \(next) is up. That'd be great.",
            "Mmmkay, coffee's done. \(next). Thanks.",
        ], seed)
    }

    public static func meetingSoon(title: String, minutes: Int, seed: Int) -> String {
        let when = minutes <= 1 ? "in a minute" : "in \(minutes) minutes"
        return pick([
            "Oh, and I almost forgot. You've got \(title) \(when). So if you could be there, that'd be great.",
            "Yeahhh, \(title) starts \(when). Go ahead and wrap up what you're doing.",
            "Just a reminder, \(title) is \(when). Mmmkay?",
        ], seed)
    }

    public static func meetingNow(title: String) -> String {
        "\(title) is starting. I paused your timer. Go ahead and head over."
    }

    public static func endOfDay(pomodoros: Int, minutes: Int) -> String {
        if pomodoros == 0 {
            return "That's the day. Zero focus blocks. We're gonna need to talk about your TPS reports."
        }
        return "That's the day. \(pomodoros) focus block\(pomodoros == 1 ? "" : "s"), \(minutes) minutes of real work. Go ahead and go home."
    }

    public static func overbooked(minutes: Int) -> String {
        "Yeahhh, you've got about \(format(minutes)) more work than day. I'm gonna need you to come in on Saturday."
    }

    public static func running(seed: Int) -> String {
        pick([
            "Great. Keep that up.",
            "Mmmkay. Head down.",
            "That'd be great. Just like that.",
        ], seed)
    }

    public static func format(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}
