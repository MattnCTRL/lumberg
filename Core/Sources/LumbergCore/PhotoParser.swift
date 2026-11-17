import Foundation

/// An event read off a photo of a calendar that has no feed.
public struct ImportedEvent: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var location: String?

    public init(id: UUID = UUID(), title: String, start: Date, end: Date, isAllDay: Bool = false, location: String? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
    }

    public var agendaEvent: AgendaEvent {
        AgendaEvent(id: "photo-\(id.uuidString)", title: title, start: start, end: end,
                    isAllDay: isAllDay, source: PhotoParser.name, colorHex: "#D7261E", location: location)
    }
}

public enum PhotoParser {
    struct Payload: Decodable {
        struct Item: Decodable {
            var title: String
            var date: String
            var start_time: String
            var end_time: String
            var all_day: Bool
            var location: String
        }
        var events: [Item]
        var notes: String
    }

    public struct Result: Equatable, Sendable {
        public var events: [ImportedEvent]
        public var notes: String
    }

    /// The JSON schema the model is held to. Every field is required; empty string means unknown.
    public static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "events": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string"],
                        "date": ["type": "string", "description": "YYYY-MM-DD"],
                        "start_time": ["type": "string", "description": "24-hour HH:MM, empty if all day"],
                        "end_time": ["type": "string", "description": "24-hour HH:MM, empty if unknown"],
                        "all_day": ["type": "boolean"],
                        "location": ["type": "string", "description": "empty if none shown"],
                    ],
                    "required": ["title", "date", "start_time", "end_time", "all_day", "location"],
                    "additionalProperties": false,
                ] as [String: Any],
            ] as [String: Any],
            "notes": ["type": "string", "description": "Anything unreadable or uncertain, one short sentence. Empty if none."],
        ] as [String: Any],
        "required": ["events", "notes"],
        "additionalProperties": false,
    ]

    public static func prompt(today: Date, calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEEE, yyyy-MM-dd"
        return """
        This is a photo or screenshot of a work calendar (usually Outlook: day, work-week, week or month view). \
        Extract every event you can read.

        Today is \(f.string(from: today)). Resolve each event to a concrete date. If the image shows weekday \
        names or day numbers without a year, pick the dates closest to today that match what is shown. \
        If it shows a single day with no date at all, assume today.

        Read start and end times from the time gutter and the edges of each event box, not only from text \
        inside the box. Use 24-hour HH:MM. If an end time cannot be told, leave end_time empty. \
        Mark banner events across the top of a day as all_day. Skip cancelled events. Keep titles exactly as \
        written, without the organizer's name or the location. Do not invent events; if part of the image is \
        unreadable, say so in notes.
        """
    }

    /// What imported events are filed under. The app sets this from its local config.
    public static var name = "Photo"

    /// The time zone the photographed calendar shows its times in, wherever it is read from.
    /// This Mac's zone unless the local config names another.
    public static var zone = TimeZone.current

    /// How far a time read off the photographed calendar sits from the same clock reading here, at that moment.
    public static func shift(at date: Date, from zone: TimeZone = PhotoParser.zone, to local: TimeZone = .current) -> TimeInterval {
        TimeInterval(local.secondsFromGMT(for: date) - zone.secondsFromGMT(for: date))
    }

    /// - Parameters:
    ///   - calendar: this Mac's calendar; all-day events keep their date in it.
    ///   - zone: the time zone the photographed calendar shows its times in.
    public static func parse(json: Data, calendar: Calendar = .current, zone: TimeZone = PhotoParser.zone) throws -> Result {
        let payload = try JSONDecoder().decode(Payload.self, from: json)
        var there = calendar
        there.timeZone = zone
        var out: [ImportedEvent] = []
        for item in payload.events {
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, let here = date(item.date, calendar: calendar),
                  let day = date(item.date, calendar: there) else { continue }
            let location = item.location.trimmingCharacters(in: .whitespaces)
            if item.all_day || time(item.start_time) == nil {
                out.append(ImportedEvent(title: title, start: here, end: here.addingTimeInterval(86_400),
                                         isAllDay: true, location: location.isEmpty ? nil : location))
                continue
            }
            let startMin = time(item.start_time)!
            let start = day.addingTimeInterval(Double(startMin) * 60)
            var end = start.addingTimeInterval(30 * 60)
            if let endMin = time(item.end_time), endMin > startMin {
                end = day.addingTimeInterval(Double(endMin) * 60)
            }
            out.append(ImportedEvent(title: title, start: start, end: end, isAllDay: false,
                                     location: location.isEmpty ? nil : location))
        }
        out.sort { $0.start < $1.start }
        return Result(events: out, notes: payload.notes)
    }

    static func date(_ s: String, calendar: Calendar) -> Date? {
        let parts = s.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func time(_ s: String) -> Int? {
        let parts = s.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        return parts[0] * 60 + parts[1]
    }
}
