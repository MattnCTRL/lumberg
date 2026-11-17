import AppKit
import EventKit
import LumbergCore

struct CalendarInfo: Identifiable, Equatable {
    var id: String
    var title: String
    var account: String
    var colorHex: String
    var defaultOn: Bool
}

/// Reads whatever calendars macOS knows about. Any account added in
/// System Settings > Internet Accounts (Google, Exchange, iCloud) shows up here.
@MainActor
final class CalendarService {
    let store = EKEventStore()
    var onChange: (() -> Void)?

    init() {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.onChange?() }
        }
    }

    var status: EKAuthorizationStatus { EKEventStore.authorizationStatus(for: .event) }
    var hasAccess: Bool { status == .fullAccess }

    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    func calendars() -> [CalendarInfo] {
        guard hasAccess else { return [] }
        return store.calendars(for: .event).map {
            CalendarInfo(
                id: $0.calendarIdentifier, title: $0.title, account: $0.source?.title ?? "",
                colorHex: Self.hex($0.cgColor),
                defaultOn: $0.type != .birthday && !$0.title.localizedCaseInsensitiveContains("holiday"))
        }
        .sorted { ($0.account, $0.title) < ($1.account, $1.title) }
    }

    func events(on day: Date, enabled: [String]?) -> [AgendaEvent] {
        guard hasAccess else { return [] }
        let wanted = Set(enabled ?? calendars().filter(\.defaultOn).map(\.id))
        let chosen = store.calendars(for: .event).filter { wanted.contains($0.calendarIdentifier) }
        guard !chosen.isEmpty else { return [] }
        let start = Calendar.current.startOfDay(for: day)
        let predicate = store.predicateForEvents(withStart: start, end: start.addingTimeInterval(86_400), calendars: chosen)
        return store.events(matching: predicate).compactMap { e in
            if e.status == .canceled { return nil }
            if let me = e.attendees?.first(where: { $0.isCurrentUser }), me.participantStatus == .declined { return nil }
            return AgendaEvent(
                id: "\(e.calendarItemIdentifier)-\(Int(e.startDate.timeIntervalSinceReferenceDate))",
                title: e.title ?? "(no title)", start: e.startDate, end: e.endDate, isAllDay: e.isAllDay,
                source: e.calendar.title, colorHex: Self.hex(e.calendar.cgColor), location: e.location)
        }
    }

    static func hex(_ color: CGColor?) -> String {
        guard let color, let rgb = NSColor(cgColor: color)?.usingColorSpace(.sRGB) else { return "#7FA7C9" }
        return String(format: "#%02X%02X%02X",
                      Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255), Int(rgb.blueComponent * 255))
    }
}
