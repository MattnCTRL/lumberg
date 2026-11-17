import XCTest
@testable import LumbergCore

final class PlannerTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }()

    func at(_ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: h, minute: m))!
    }

    func meeting(_ id: String, _ s: Date, _ e: Date) -> AgendaEvent {
        AgendaEvent(id: id, title: id, start: s, end: e, source: "Work")
    }

    func testFillsFreeTimeWithPomodorosAndBreaks() {
        let tasks = [TaskItem(title: "A", estimateMinutes: 50)]
        let plan = Planner.plan(now: at(9), events: [], tasks: tasks, settings: PlannerSettings(), calendar: cal)
        XCTAssertEqual(plan.blocks.map(\.kind), [.focus, .shortBreak, .focus])
        XCTAssertEqual(plan.blocks[0].start, at(9))
        XCTAssertEqual(plan.blocks[0].end, at(9, 25))
        XCTAssertEqual(plan.blocks[2].start, at(9, 30))
        XCTAssertEqual(plan.blocks[2].end, at(9, 55))
        XCTAssertTrue(plan.unscheduled.isEmpty)
    }

    func testFocusNeverOverlapsMeetingOrItsBuffer() {
        let tasks = [TaskItem(title: "A", estimateMinutes: 240)]
        let events = [meeting("standup", at(9, 30), at(10)), meeting("review", at(13), at(14, 30))]
        let s = PlannerSettings()
        let plan = Planner.plan(now: at(8, 2), events: events, tasks: tasks, settings: s, calendar: cal)
        let focus = plan.focusBlocks
        XCTAssertFalse(focus.isEmpty)
        for f in focus {
            for e in events {
                let guardStart = e.start.addingTimeInterval(-Double(s.meetingBufferMinutes) * 60)
                XCTAssertFalse(f.start < e.end && f.end > guardStart, "\(f.start)–\(f.end) hits \(e.title)")
            }
            XCTAssertGreaterThanOrEqual(f.minutes, s.minFocusMinutes)
            XCTAssertGreaterThanOrEqual(f.start, at(8, 5))
            XCTAssertLessThanOrEqual(f.end, at(17))
        }
        XCTAssertEqual(plan.blocks.filter { $0.kind == .meeting }.count, 2)
    }

    func testPriorityOrderAndOverflow() {
        let low = TaskItem(title: "low", estimateMinutes: 60, priority: 3)
        let high = TaskItem(title: "high", estimateMinutes: 60, priority: 1)
        let plan = Planner.plan(now: at(15, 30), events: [], tasks: [low, high], settings: PlannerSettings(), calendar: cal)
        XCTAssertEqual(plan.focusBlocks.first?.taskID, high.id)
        XCTAssertEqual(plan.freeMinutes, 90)
        XCTAssertEqual(plan.demandMinutes, 120)
        XCTAssertEqual(plan.unscheduled.map(\.taskID), [low.id])
        XCTAssertGreaterThan(plan.overMinutes, 0)
    }

    func testProjectsTakeTurnsAndSpentBlocksStepAside() {
        let a = UUID(), b = UUID()
        var first = TaskItem(title: "A", estimateMinutes: 100, order: 1, projectID: a, isBlock: true)
        let second = TaskItem(title: "B", estimateMinutes: 50, order: 2, projectID: b, isBlock: true)
        var plan = Planner.plan(now: at(9), events: [], tasks: [first, second], settings: PlannerSettings(), calendar: cal)
        XCTAssertEqual(plan.focusBlocks.prefix(6).map(\.title), ["A", "A", "B", "B", "A", "A"])
        // A has used up its time for the day: B is next, and A asks for nothing more.
        first.spentSeconds = 100 * 60
        plan = Planner.plan(now: at(9), events: [], tasks: [first, second], settings: PlannerSettings(), calendar: cal)
        XCTAssertEqual(Set(plan.focusBlocks.map(\.title)), ["B"])
    }

    func testLongBreakAfterFourthCycle() {
        let tasks = [TaskItem(title: "A", estimateMinutes: 200)]
        let plan = Planner.plan(now: at(9), events: [], tasks: tasks, settings: PlannerSettings(), cyclesDone: 3, calendar: cal)
        XCTAssertEqual(plan.blocks[1].kind, .longBreak)
        XCTAssertEqual(plan.blocks[1].minutes, 15)
    }

    func testNothingAfterHoursAndRespectsNotBefore() {
        let tasks = [TaskItem(title: "A", estimateMinutes: 50)]
        XCTAssertTrue(Planner.plan(now: at(18), events: [], tasks: tasks, settings: PlannerSettings(), calendar: cal).focusBlocks.isEmpty)
        let plan = Planner.plan(now: at(9), events: [], tasks: tasks, settings: PlannerSettings(), notBefore: at(9, 42), calendar: cal)
        XCTAssertEqual(plan.focusBlocks.first?.start, at(9, 45))
    }

    func testDoneTasksAndAllDayEventsIgnored() {
        let done = TaskItem(title: "done", isDone: true)
        let allDay = AgendaEvent(id: "x", title: "Holiday", start: at(0), end: at(23, 59), isAllDay: true, source: "c")
        let plan = Planner.plan(now: at(9), events: [allDay], tasks: [done], settings: PlannerSettings(), calendar: cal)
        XCTAssertTrue(plan.blocks.isEmpty)
        XCTAssertEqual(plan.freeMinutes, 480)
    }
}

final class TaskParserTests: XCTestCase {
    func testFullSyntax() {
        let t = TaskParser.parse("TPS cover sheets 50m !1 #work")!
        XCTAssertEqual(t.title, "TPS cover sheets")
        XCTAssertEqual(t.estimateMinutes, 50)
        XCTAssertEqual(t.priority, 1)
        XCTAssertEqual(t.tag, WorkTag("work"))
    }

    func testDurations() {
        XCTAssertEqual(TaskParser.duration("1h30m"), 90)
        XCTAssertEqual(TaskParser.duration("1.5h"), 90)
        XCTAssertEqual(TaskParser.duration("2h"), 120)
        XCTAssertNil(TaskParser.duration("v2"))
        XCTAssertNil(TaskParser.duration("3"))
    }

    func testDefaultsAndUnknownTokensStayInTitle() {
        let t = TaskParser.parse("Fix issue #42 for Q3!")!
        XCTAssertEqual(t.title, "Fix issue #42 for Q3!")
        XCTAssertEqual(t.estimateMinutes, 25)
        XCTAssertEqual(t.priority, 2)
        XCTAssertNil(TaskParser.parse("  50m  "))
    }
}

final class PhotoParserTests: XCTestCase {
    func testParsesTimedAllDayAndBadRows() throws {
        let pacific = TimeZone(identifier: "America/Los_Angeles")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = pacific
        let json = """
        {"events":[
          {"title":"Calibration","date":"2026-11-17","start_time":"13:00","end_time":"14:30","all_day":false,"location":"Teams"},
          {"title":"Standup","date":"2026-11-17","start_time":"09:00","end_time":"","all_day":false,"location":""},
          {"title":"Furlough day","date":"2026-11-18","start_time":"","end_time":"","all_day":true,"location":""},
          {"title":"","date":"2026-11-18","start_time":"10:00","end_time":"11:00","all_day":false,"location":""},
          {"title":"Bad date","date":"soon","start_time":"10:00","end_time":"11:00","all_day":false,"location":""}
        ],"notes":"bottom row cut off"}
        """.data(using: .utf8)!
        let r = try PhotoParser.parse(json: json, calendar: cal, zone: pacific)
        XCTAssertEqual(r.events.map(\.title), ["Standup", "Calibration", "Furlough day"])
        XCTAssertEqual(r.events[0].end.timeIntervalSince(r.events[0].start), 1800)
        XCTAssertEqual(r.events[1].end.timeIntervalSince(r.events[1].start), 5400)
        XCTAssertEqual(r.events[1].location, "Teams")
        XCTAssertTrue(r.events[2].isAllDay)
        XCTAssertEqual(r.notes, "bottom row cut off")

        // 13:00 on a Pacific calendar is 15:00 Central, and an all-day event stays on its date.
        var central = Calendar(identifier: .gregorian)
        central.timeZone = TimeZone(identifier: "America/Chicago")!
        let c = try PhotoParser.parse(json: json, calendar: central, zone: pacific)
        let moved = central.dateComponents([.day, .hour, .minute], from: c.events[1].start)
        XCTAssertEqual([moved.day, moved.hour, moved.minute], [17, 15, 0])
        XCTAssertEqual(c.events[1].start, r.events[1].start)
        let off = central.dateComponents([.day, .hour], from: c.events[2].start)
        XCTAssertEqual([off.day, off.hour], [18, 0])
        XCTAssertEqual(PhotoParser.shift(at: c.events[1].start, from: pacific, to: central.timeZone), 7200)
    }
}

final class PortraitTests: XCTestCase {
    func testOutfitPartsAreAllPresentAndTheFaceIsPlain() {
        let parts = AsciiPortrait.parts(cols: 110, rows: 52).flatMap { $0 }
        XCTAssertTrue(parts.contains(.suspenders))
        XCTAssertTrue(parts.contains(.tie))
        XCTAssertTrue(parts.contains(.mug))
        let face = AsciiPortrait.parts(cols: 40, rows: 21, view: AsciiPortrait.faceView).flatMap { $0 }
        XCTAssertTrue(face.allSatisfy { $0 == .plain })
    }
}

final class ProjectFieldTests: XCTestCase {
    func testDataSavedBeforeProjectsStillLoads() throws {
        let old = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","title":"TPS","estimateMinutes":25,"spentSeconds":0,"priority":2,"isDone":false,"createdAt":0,"order":1}"#
        let task = try JSONDecoder().decode(TaskItem.self, from: Data(old.utf8))
        XCTAssertNil(task.projectID)
    }

    func testProjectSurvivesARoundTrip() throws {
        let project = UUID()
        let task = TaskItem(title: "Rubric", projectID: project)
        let session = LoggedSession(kind: .focus, title: "Rubric", taskID: task.id, projectID: project,
                                    start: Date(), end: Date().addingTimeInterval(60))
        XCTAssertEqual(try JSONDecoder().decode(TaskItem.self, from: JSONEncoder().encode(task)).projectID, project)
        XCTAssertEqual(try JSONDecoder().decode(LoggedSession.self, from: JSONEncoder().encode(session)).projectID, project)
    }
}

final class ProjectPlannerTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        return c
    }()
    /// Monday 2026-11-16.
    var monday: Date { cal.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 9))! }

    func load(_ name: String, target: Int, logged: Int = 0, planned: Int = 0, priority: Int = 2,
              status: ProjectStatus = .active, tasks: [Int] = []) -> ProjectLoad {
        let p = Project(name: name, weeklyTargetMinutes: target, priority: priority, status: status)
        return ProjectLoad(project: p, loggedMinutes: logged, plannedMinutes: planned,
                           candidates: tasks.map { TaskItem(title: "\(name) \($0)", estimateMinutes: $0, projectID: p.id) })
    }

    func testWorkdaysLeft() {
        XCTAssertEqual(ProjectPlanner.workdaysLeft(from: monday, calendar: cal), 5)
        XCTAssertEqual(ProjectPlanner.workdaysLeft(from: monday.addingTimeInterval(4 * 86_400), calendar: cal), 1)
        XCTAssertEqual(ProjectPlanner.workdaysLeft(from: monday.addingTimeInterval(5 * 86_400), calendar: cal), 1)
    }

    func testShareIsWeeklyTargetSpreadOverTheWeek() {
        let a = load("A", target: 300)
        let p = ProjectPlanner.propose(loads: [a], freeMinutes: 480, today: monday, calendar: cal)
        XCTAssertEqual(p.shares[a.project.id], 60)
        XCTAssertEqual(p.lines.count, 1)
        XCTAssertNil(p.lines[0].taskID)
        XCTAssertEqual(p.lines[0].minutes, 60)
    }

    func testLoggedAndAlreadyPlannedTimeReduceTheShare() {
        let a = load("A", target: 300, logged: 100, planned: 20)
        let p = ProjectPlanner.propose(loads: [a], freeMinutes: 480, today: monday, calendar: cal)
        XCTAssertEqual(p.shares[a.project.id], 20)
    }

    func testSharesShrinkToFitOpenTimeAndKeepTheirProportions() {
        let a = load("A", target: 600), b = load("B", target: 300)
        let p = ProjectPlanner.propose(loads: [a, b], freeMinutes: 100, today: monday, calendar: cal)
        XCTAssertLessThanOrEqual(p.shares.values.reduce(0, +), p.budgetMinutes)
        XCTAssertEqual(p.shares[a.project.id], 55)
        XCTAssertEqual(p.shares[b.project.id], 25)
    }

    func testPausedProjectsGetNothingAndTasksFillTheShareFirst() {
        let a = load("A", target: 300, tasks: [25, 25, 50]), b = load("B", target: 300, status: .paused)
        let p = ProjectPlanner.propose(loads: [a, b], freeMinutes: 480, today: monday, calendar: cal)
        XCTAssertNil(p.shares[b.project.id])
        XCTAssertEqual(p.lines.map(\.minutes), [25, 25])
        XCTAssertTrue(p.lines.allSatisfy { $0.taskID != nil })
    }

    func testAnOversizedFirstTaskStillGoesInButNothingElseDoes() {
        let a = load("A", target: 300, tasks: [90, 25])
        let p = ProjectPlanner.propose(loads: [a], freeMinutes: 480, today: monday, calendar: cal)
        XCTAssertEqual(p.lines.map(\.minutes), [90])
    }

    func testQuickAddPicksUpTheProjectWord() {
        let r = TaskParser.parseWithProject("Draft rubric 90m @Rubric")
        XCTAssertEqual(r?.project, "rubric")
        XCTAssertEqual(r?.task.title, "Draft rubric")
        XCTAssertEqual(r?.task.estimateMinutes, 90)
    }
}

final class WorkEvidenceTests: XCTestCase {
    func testClaudeDirName() {
        XCTAssertEqual(WorkEvidence.claudeDirName(for: "/Users/me/my_app.v2"), "-Users-me-my-app-v2")
    }

    func testGitLogMarksFocusTime() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let window = DateInterval(start: start, duration: 1500)
        let log = "abc1234\u{1f}1000600\u{1f}Fix the thing\ndef5678\u{1f}1009000\u{1f}Later: tidy up"
        let commits = WorkEvidence.parseGitLog(log, windows: [window])
        XCTAssertEqual(commits.map(\.subject), ["Fix the thing", "Later: tidy up"])
        XCTAssertEqual(commits.map(\.inFocus), [true, false])
    }

    func testGitStatusPaths() {
        XCTAssertEqual(WorkEvidence.parseGitStatus(" M a/b.swift\n?? new.txt\nR  old.txt -> moved.txt"),
                       ["a/b.swift", "new.txt", "moved.txt"])
    }

    func testTranscriptLines() {
        func event(_ json: String) -> WorkEvidence.TranscriptEvent? {
            WorkEvidence.parseTranscriptLine(Data(json.utf8))
        }
        let asked = event(#"{"type":"user","timestamp":"2026-11-16T17:29:00.123Z","cwd":"/p","message":{"role":"user","content":"Add a projects screen"}}"#)
        XCTAssertEqual(asked?.prompt, "Add a projects screen")
        XCTAssertEqual(asked?.cwd, "/p")
        let edit = event(#"{"type":"assistant","timestamp":"2026-11-16T17:30:00Z","cwd":"/p","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/p/a.swift"}}]}}"#)
        XCTAssertEqual(edit?.editedFiles, ["/p/a.swift"])
        XCTAssertNil(event(#"{"type":"user","timestamp":"2026-11-16T17:30:00Z","message":{"content":[{"type":"tool_result","content":"ok"}]}}"#))
        XCTAssertNil(event(#"{"type":"user","isMeta":true,"timestamp":"2026-11-16T17:30:00Z","message":{"content":"note"}}"#))
        XCTAssertNil(event(#"{"type":"user","timestamp":"2026-11-16T17:30:00Z","message":{"content":"<command-name>/clear</command-name>"}}"#))
        XCTAssertEqual(WorkEvidence.relative("/p/a.swift", to: "/p"), "a.swift")
    }

    func testUnplannedWork() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        func at(_ m: Double) -> Date { t0.addingTimeInterval(m * 60) }
        // Three moments close together, a long gap, then one alone.
        let spans = WorkEvidence.spans([at(0), at(10), at(20), at(120)])
        XCTAssertEqual(spans.count, 2)
        XCTAssertEqual(WorkEvidence.minutes(spans), 25)
        // A focus block covering minutes 5 to 15 leaves the rest unplanned.
        let off = WorkEvidence.outside(spans, windows: [DateInterval(start: at(5), end: at(15))])
        XCTAssertEqual(off.map { Int($0.duration / 60) }, [5, 5, 5])
        XCTAssertTrue(WorkEvidence.outside(spans, windows: [DateInterval(start: at(-1), end: at(130))]).isEmpty)

        let activity = WorkEvidence.parseActivity("2026-11-16T17:13:39.687Z\t/Users/m/portal\n2026-11-16T17:20:00.000Z\t/Users/m/portal/notes\n2026-11-16T17:21:00.000Z\t/Users/m\n2026-11-16T17:22:00.000Z\t/Users/m/lumberg/Core\n2026-11-16T17:22:00.000Z\t/Users/m/.claude/x\nrubbish")
        XCTAssertEqual(activity.count, 5)
        let strays = WorkEvidence.strays(activity, home: "/Users/m", known: ["~/lumberg"])
        XCTAssertEqual(strays.map(\.folder), ["/Users/m/portal"])
        XCTAssertEqual(strays.first?.minutes, 6)
        XCTAssertEqual(strays.first?.name, "portal")
    }

    func testSessionNoteNames() {
        let note = WorkEvidence.parseNoteName("2026-11-10 1005 - September report built.md")
        XCTAssertEqual(note?.topic, "September report built")
        let c = Calendar.current.dateComponents([.month, .day, .hour, .minute], from: note!.date)
        XCTAssertEqual([c.month, c.day, c.hour, c.minute], [11, 10, 10, 5])
        XCTAssertNil(WorkEvidence.parseNoteName("_TEMPLATE.md"))
        let words = WorkEvidence.keywords(["Ops rubric", "Ops Rubric Work"])
        XCTAssertEqual(words, ["ops", "rubric"])
        XCTAssertTrue(WorkEvidence.note("rubric v0.7 from the October 9 meetings", mentions: words))
        XCTAssertFalse(WorkEvidence.note("badge access revision 3", mentions: words))
    }
}

final class DossierTests: XCTestCase {
    let sample = """
    ---
    lumberg: 1
    slug: portal
    name: "Portal: client rollout"
    client: client
    status: active
    priority: 1
    weekly_hours: 6
    deadline: 2026-12-23
    folder: ~/portal
    host:
    remote: github.com/example/portal
    also: [~/x, studio:~/y]
    ---

    # Portal

    ## What it is

    Reads certificate requests
    and answers the standard ones.

    Second paragraph.

    ## Log

    - 2026-11-17: Dossier created.

    ## After

    Kept.

    """

    func testRoundTripLeavesTheFileAlone() {
        let d = Dossier(text: sample)
        XCTAssertEqual(d.text, sample)
        XCTAssertEqual(d["name"], "Portal: client rollout")
        XCTAssertEqual(d["also"], "[~/x, studio:~/y]")
        XCTAssertNil(d["host"])
        XCTAssertTrue(d.isTracked)
        XCTAssertEqual(d.summary, "Reads certificate requests and answers the standard ones.")
        let plain = Dossier(text: "# No header\n")
        XCTAssertFalse(plain.isTracked)
        XCTAssertEqual(plain.text, "# No header\n")
    }

    func testHeaderAndProject() {
        var d = Dossier(text: sample)
        var p = Project(name: "x", folder: "/old", host: "studio")
        d.apply(to: &p)
        XCTAssertEqual(p.name, "Portal: client rollout")
        XCTAssertEqual(p.client, WorkTag("client"))
        XCTAssertEqual(p.priority, 1)
        XCTAssertEqual(p.weeklyTargetMinutes, 360)
        XCTAssertEqual(p.folder, "~/portal")
        XCTAssertNil(p.host)
        let c = Calendar.current.dateComponents([.year, .month, .day], from: p.deadline!)
        XCTAssertEqual([c.year, c.month, c.day], [2026, 12, 23])

        // Writing the same project back changes nothing, so the file is not rewritten.
        XCTAssertFalse(d.take(from: p, slug: "portal"))
        XCTAssertEqual(d.text, sample)

        p.weeklyTargetMinutes = 90
        p.status = .paused
        p.deadline = nil
        p.client = nil
        XCTAssertTrue(d.take(from: p, slug: "portal"))
        XCTAssertEqual(d["weekly_hours"], "1.5")
        XCTAssertEqual(d["status"], "paused")
        XCTAssertEqual(d["remote"], "github.com/example/portal")
        var q = Project(name: "y", client: WorkTag("work"), deadline: Date())
        Dossier(text: d.text).apply(to: &q)
        XCTAssertNil(q.deadline)
        XCTAssertNil(q.client)
        XCTAssertEqual(q.status, .paused)

        d["status"] = Dossier.removed
        XCTAssertFalse(d.isTracked)
        XCTAssertEqual(Dossier.slug("Acme Consulting App"), "acme-consulting-app")
        XCTAssertEqual(Dossier.quoted("a: b"), "\"a: b\"")
        XCTAssertEqual(Dossier.quoted("~/Developer/portal"), "~/Developer/portal")
    }

    func testAutoBlockAndLog() {
        var d = Dossier(text: sample)
        XCTAssertTrue(d.setAuto("## Tracked by Lumberg\n\n- one"))
        XCTAssertFalse(d.setAuto("## Tracked by Lumberg\n\n- one"))
        XCTAssertEqual(d.auto, "## Tracked by Lumberg\n\n- one")
        // The block goes in just above the log, and a second write replaces it in place.
        XCTAssertTrue(d.body.range(of: Dossier.autoEnd)!.lowerBound < d.body.range(of: "## Log")!.lowerBound)
        d.setAuto("- two")
        XCTAssertEqual(d.auto, "- two")
        XCTAssertEqual(d.body.components(separatedBy: Dossier.autoStart).count, 2)

        d.appendLog("Shipped the\nconsole", day: "2026-11-18")
        XCTAssertTrue(d.body.contains("- 2026-11-17: Dossier created.\n- 2026-11-18: Shipped the console\n\n## After\n\nKept."))
        XCTAssertEqual(Dossier(text: d.text), d)

        var bare = Dossier(text: "---\nlumberg: 1\nname: A\n---\n\n# A\n")
        bare.appendLog("first", day: "2026-11-18")
        bare.setAuto("- t")
        XCTAssertTrue(bare.body.hasSuffix("## Log\n\n- 2026-11-18: first\n"))
        XCTAssertTrue(bare.body.range(of: Dossier.autoEnd)!.lowerBound < bare.body.range(of: "## Log")!.lowerBound)

        let made = Dossier.template(for: Project(name: "New Thing", client: WorkTag("personal"), weeklyTargetMinutes: 0), slug: "new-thing", day: "2026-11-18")
        XCTAssertTrue(Dossier(text: made.text).isTracked)
        XCTAssertEqual(made["weekly_hours"], "0")
        let block = Dossier.tracked(project: Project(name: "A", weeklyTargetMinutes: 120), weekOf: "2026-11-16", weekMinutes: 75,
                                    fourWeekMinutes: 200, lastFocus: "2026-11-17", openTasks: ["one"],
                                    days: [.init(day: "2026-11-17", workedMinutes: 90, commits: 3, requests: 12, summary: "Did a | b")])
        XCTAssertTrue(block.contains("1h 15m of focus time logged of 2h budgeted"))
        XCTAssertTrue(block.contains("| 2026-11-17 | 1h 30m | 3 | 12 | Did a / b |"))
    }
}
