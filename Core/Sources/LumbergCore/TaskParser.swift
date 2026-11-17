import Foundation

/// Quick-add syntax: `TPS cover sheets 50m !1 #work`.
/// Durations: 25m, 90min, 2h, 1.5h, 1h30m. Priority: !1 !2 !3. Tag: `#` and a tag's id or one of its aliases. Project: @name.
public enum TaskParser {
    static var tagAliases: [String: WorkTag] {
        var out: [String: WorkTag] = [:]
        for d in WorkTag.definitions {
            for word in [d.id] + d.aliases { out[word.lowercased()] = WorkTag(d.id) }
        }
        return out
    }

    public static func parse(_ input: String) -> TaskItem? {
        parseWithProject(input)?.task
    }

    /// Also returns the `@project` word, lower-cased and without the `@`, if there was one.
    public static func parseWithProject(_ input: String) -> (task: TaskItem, project: String?)? {
        var project: String?
        var words: [String] = []
        var estimate: Int?
        var priority = 2
        var tag: WorkTag?

        for raw in input.split(whereSeparator: { $0 == " " || $0 == "\t" }) {
            let token = String(raw)
            let lower = token.lowercased()
            if lower.hasPrefix("#"), let t = tagAliases[String(lower.dropFirst())] {
                tag = t
            } else if lower.hasPrefix("@"), lower.count > 1, project == nil {
                project = String(lower.dropFirst())
            } else if lower.hasPrefix("!"), let p = Int(lower.dropFirst()), (1...3).contains(p) {
                priority = p
            } else if let minutes = duration(lower) {
                estimate = minutes
            } else {
                words.append(token)
            }
        }

        let title = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        return (TaskItem(title: title, estimateMinutes: estimate ?? 25, priority: priority, tag: tag), project)
    }

    /// Minutes for tokens like `25m`, `2h`, `1.5h`, `1h30m`; nil for anything else.
    static func duration(_ token: String) -> Int? {
        var rest = Substring(token)
        var total = 0.0
        var matched = false
        while !rest.isEmpty {
            let number = rest.prefix { $0.isNumber || $0 == "." }
            guard !number.isEmpty, let value = Double(number) else { return nil }
            rest = rest.dropFirst(number.count)
            let unit = rest.prefix { $0.isLetter }
            rest = rest.dropFirst(unit.count)
            switch unit {
            case "m", "min", "mins": total += value
            case "h", "hr", "hrs": total += value * 60
            default: return nil
            }
            matched = true
        }
        let minutes = Int(total.rounded())
        return matched && minutes > 0 && minutes <= 12 * 60 ? minutes : nil
    }
}
