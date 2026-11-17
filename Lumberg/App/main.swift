import AppKit
import LumbergCore

// `Lumberg --read-photo <image>` reads one calendar photo, prints the events and exits,
// without opening the app. `--scan` does the same for a project folder. Everything else starts the app.
let arguments = CommandLine.arguments
LocalConfig.load()
if let i = arguments.firstIndex(of: "--read-photo"), i + 1 < arguments.count {
    guard let image = NSImage(contentsOfFile: arguments[i + 1]) else {
        print("Could not open \(arguments[i + 1])")
        exit(2)
    }
    Task {
        do {
            let result = try await PhotoInterpreter.interpret(image: image, model: Store.load().settings.model)
            let f = DateFormatter()
            f.dateFormat = "EEE MMM d  HH:mm"
            for e in result.events {
                print(e.isAllDay ? "\(f.string(from: e.start).prefix(10))  all day     \(e.title)"
                                 : "\(f.string(from: e.start))-\(f.string(from: e.end).suffix(5))  \(e.title)")
            }
            print("\(result.events.count) events. \(result.notes)")
            exit(0)
        } catch {
            print(error.localizedDescription)
            exit(1)
        }
    }
    RunLoop.main.run()
} else if let i = arguments.firstIndex(of: "--agenda"), i + 1 < arguments.count {
    // `Lumberg --agenda <file>` writes today's events from the calendars and the photo imports to a file and exits.
    let out = arguments[i + 1]
    Task { @MainActor in
        let service = CalendarService()
        let saved = Store.load()
        var lines = ["calendar access: \(service.hasAccess ? "yes" : "NO (\(service.status.rawValue))")"]
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        let day = Calendar.current.startOfDay(for: Date())
        var events = service.events(on: Date(), enabled: saved.settings.enabledCalendarIDs)
        events += saved.photoEvents.filter { $0.start < day.addingTimeInterval(86_400) && $0.end > day }.map { e -> AgendaEvent in
            AgendaEvent(id: e.id.uuidString, title: e.title, start: e.start, end: e.end, isAllDay: e.isAllDay, source: "\(PhotoParser.name) (photo)")
        }
        for e in events.sorted(by: { $0.start < $1.start }) {
            lines.append(e.isAllDay ? "all day      [\(e.source)] \(e.title)" : "\(f.string(from: e.start))-\(f.string(from: e.end))  [\(e.source)] \(e.title)")
        }
        lines.append("calendars: " + service.calendars().map { "\($0.account)/\($0.title)\($0.defaultOn ? "" : " (off)")" }.joined(separator: ", "))
        try? lines.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
        exit(0)
    }
    RunLoop.main.run()
} else if let i = arguments.firstIndex(of: "--scan"), i + 1 < arguments.count {
    // `Lumberg --scan <folder> [ssh host or ""] [project name]` prints what a project folder shows for the last week.
    let host = i + 2 < arguments.count && !arguments[i + 2].isEmpty ? arguments[i + 2] : nil
    let name = i + 3 < arguments.count ? arguments[i + 3] : ""
    Task {
        do {
            let found = try await WorkScanner.scan(projectID: UUID(), name: name, folder: arguments[i + 1], host: host,
                                                   windows: [], today: Date())
            for s in await WorkScanner.strays(host: host, known: [arguments[i + 1]], today: Date()) {
                print("Not budgeted today: \(s.folder), about \(Quotes.format(s.minutes))")
            }
            for c in found {
                print("About \(Quotes.format(WorkEvidence.minutes(c.active ?? []))) of work")
                print(WorkEvidence.digest(c, project: arguments[i + 1]) { Fmt.timeAMPM.string(from: $0) })
                print("")
            }
            exit(0)
        } catch {
            print(error.localizedDescription)
            exit(1)
        }
    }
    RunLoop.main.run()
} else {
    LumbergApp.main()
}
