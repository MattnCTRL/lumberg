import AppKit
import LumbergCore
import Observation

/// Everything the app knows, plus the timer that drives the day.
@MainActor
@Observable
final class AppState {
    // Persisted.
    var tasks: [TaskItem]
    var projects: [Project]
    var captures: [WorkCapture]
    var photoEvents: [ImportedEvent]
    var settings: AppSettings
    var log: [String: DayLog]
    var session: Session?

    // Runtime.
    var now = Date()
    /// Same clock, but only changes once a minute, so the timeline does not redraw every second.
    var minuteNow = Date()
    var calendarEvents: [AgendaEvent] = []
    var calendarList: [CalendarInfo] = []
    var hasCalendarAccess = false
    var plan = DayPlan()
    var quote = ""
    var showImport = false
    var showReport = false
    enum SideTab { case today, projects }
    var sideTab = SideTab.today
    /// Bumped when a dossier is written from the app, so views showing it read it again.
    var dossierStamp = 0
    /// What Plan my day suggests; shown for approval, nothing changes until accepted.
    var proposal: Proposal?
    /// The projects screen replaces the day view while this is on.
    var showProjects = false
    var projectSelection: UUID?
    var draftingProject = false
    var scanning: Set<UUID> = []
    var writingUp: Set<String> = []
    var scanErrors: [UUID: String] = [:]
    /// Today's work in folders no project claims.
    var strays: [StrayWork] = []
    var findingStrays = false
    /// What the new-project form opens filled in with.
    var draftSeed: Project?

    @ObservationIgnored let calendars = CalendarService()
    @ObservationIgnored let nags = NagPresenter()
    @ObservationIgnored let mini = MiniPresenter()
    @ObservationIgnored weak var mainWindow: NSWindow?
    @ObservationIgnored var openMain: (() -> Void)?
    @ObservationIgnored let isDemo: Bool
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastMinute = -1
    @ObservationIgnored private var lastDay = ""
    @ObservationIgnored private var lastNag = Date()
    @ObservationIgnored private var snoozeUntil: Date?
    @ObservationIgnored private var lastDriftCheck = Date.distantPast
    @ObservationIgnored private var lastDriftNag = Date.distantPast
    @ObservationIgnored private var checkingDrift = false
    /// Projects the timer was told to stay off for now, and until when.
    @ObservationIgnored private var driftQuiet: [UUID: Date] = [:]
    @ObservationIgnored private var warned: Set<String> = []
    @ObservationIgnored private var closedDay: String?

    init() {
        isDemo = CommandLine.arguments.contains("--demo")
        let saved = Store.load()
        tasks = saved.tasks
        projects = saved.projects
        captures = saved.captures
        photoEvents = saved.photoEvents
        settings = saved.settings
        log = saved.log
        session = saved.session

        // A timer that ran out while the app was closed still counts.
        if let s = session, !s.isPaused, s.endsAt <= Date() {
            credit(until: s.endsAt)
            if s.kind == .focus { log[Store.dayKey(s.endsAt), default: DayLog()].pomodoros += 1 }
            session = nil
        }

        calendars.onChange = { [weak self] in self?.refreshCalendar() }
        if isDemo { seedDemo() }
        // `--nag` makes the first idle pop-up appear at once instead of after the usual wait.
        if CommandLine.arguments.contains("--nag") { lastNag = .distantPast }
        // `--projects [name]` opens straight onto the projects screen, on that project if named.
        if let i = CommandLine.arguments.firstIndex(of: "--projects") {
            let name = i + 1 < CommandLine.arguments.count ? CommandLine.arguments[i + 1].lowercased() : ""
            let match = projects.first { !name.isEmpty && $0.name.lowercased().hasPrefix(name) }
            openProjects(select: match?.id)
            if let match { scanWork(match.id) }
        }
        refreshCalendar()

        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        replan()
        // The first tick can raise a pop-up, and this init runs inside a SwiftUI update,
        // where building another hosting view aborts. Let the update finish first.
        DispatchQueue.main.async { [weak self] in
            self?.tick()
            self?.commit()
            self?.syncDossiers()
        }
    }

    // MARK: - Derived

    var todayKey: String { Store.dayKey(now) }
    var todayLog: DayLog { log[todayKey] ?? DayLog() }

    /// Calendar events plus photo imports, today only.
    var agenda: [AgendaEvent] {
        let start = Calendar.current.startOfDay(for: now), end = start.addingTimeInterval(86_400)
        let imported = photoEvents.filter { $0.start < end && $0.end > start }.map(\.agendaEvent)
        return (calendarEvents + imported).sorted { $0.start < $1.start }
    }

    var currentMeeting: AgendaEvent? {
        agenda.first { !$0.isAllDay && $0.start <= now && $0.end > now }
    }

    var nextMeeting: AgendaEvent? {
        agenda.first { !$0.isAllDay && $0.start > now }
    }

    var nextFocus: PlanBlock? { plan.focusBlocks.first }

    /// Today's list: loose tasks, plus project tasks that were put on today.
    var openTasks: [TaskItem] { Planner.queue(tasks.filter(isOnToday)) }

    func isOnToday(_ t: TaskItem) -> Bool {
        t.projectID == nil || t.plannedDay == todayKey
    }

    var doneToday: [TaskItem] {
        let start = Calendar.current.startOfDay(for: now)
        return tasks.filter { $0.isDone && ($0.doneAt ?? .distantPast) >= start }
    }

    /// Whether Done today holds anything Clear would remove.
    var canClearDone: Bool {
        doneToday.contains { $0.projectID == nil || $0.isBlock == true }
    }

    var mood: Mood {
        if let s = session, s.kind == .focus, !s.isPaused { return .pleased }
        if session == nil, currentMeeting == nil, nextFocus != nil, inWorkHours { return .displeased }
        return .neutral
    }

    var inWorkHours: Bool {
        let w = Planner.workWindow(for: now, settings: settings.planner)
        return now >= w.start && now < w.end
    }

    func task(_ id: UUID?) -> TaskItem? {
        guard let id else { return nil }
        return tasks.first { $0.id == id }
    }

    func isUnscheduled(_ id: UUID) -> Bool {
        plan.unscheduled.contains { $0.taskID == id }
    }

    // MARK: - Clock

    func tick() {
        now = Date()
        if let s = session, !s.isPaused, now >= s.endsAt { finishSession() }

        let minute = Int(now.timeIntervalSinceReferenceDate / 60)
        guard minute != lastMinute else { return }
        lastMinute = minute
        minuteNow = now
        if todayKey != lastDay {
            lastDay = todayKey
            // Yesterday's "work on this project" blocks were placeholders, not tasks.
            tasks.removeAll { $0.isBlock == true && $0.plannedDay != todayKey && session?.taskID != $0.id }
            refreshCalendar()
        }
        replan()
        checkMeetings()
        checkIdle()
        checkEndOfDay()
        checkDrift()
    }

    /// Call after any change to tasks, events, settings or the session.
    func commit() {
        replan()
        var p = Persisted()
        p.tasks = tasks
        p.projects = projects
        p.captures = captures
        p.photoEvents = photoEvents
        p.settings = settings
        p.log = log
        p.session = session
        Store.save(p)
    }

    func replan() {
        var planTasks = tasks.filter(isOnToday)
        var notBefore: Date?
        var cycles = todayLog.pomodoros
        if let s = session {
            let remaining = s.remaining(at: now)
            var end = now.addingTimeInterval(remaining)
            if s.kind == .focus {
                // Plan as if the running block will be finished.
                if let i = planTasks.firstIndex(where: { $0.id == s.taskID }) {
                    let live = s.isPaused ? 0 : max(0, now.timeIntervalSince(s.segmentStart))
                    let projected = planTasks[i].spentSeconds + Int(live + remaining)
                    if projected >= planTasks[i].estimateMinutes * 60 {
                        planTasks.remove(at: i)
                    } else {
                        planTasks[i].spentSeconds = projected
                    }
                }
                cycles += 1
                let p = settings.planner
                let long = cycles % max(p.cyclesBeforeLongBreak, 1) == 0
                end += Double(long ? p.longBreakMinutes : p.shortBreakMinutes) * 60
            }
            notBefore = end
        }
        plan = Planner.plan(now: now, events: agenda, tasks: planTasks, settings: settings.planner,
                            cyclesDone: cycles, notBefore: notBefore)
        updateQuote()
    }

    private func updateQuote() {
        let seed = Int(now.timeIntervalSinceReferenceDate / 600)
        if let s = session {
            switch s.kind {
            case .focus: quote = s.isPaused ? "Yeahhh, I'm gonna need you to go ahead and un-pause that." : Quotes.running(seed: seed)
            default: quote = "Go ahead and enjoy your break. I'll be by in a few minutes."
            }
        } else if let m = currentMeeting {
            quote = "You're in \(m.title). We'll talk after."
        } else if plan.overMinutes > 0 {
            quote = Quotes.overbooked(minutes: plan.overMinutes)
        } else if let next = nextFocus {
            quote = Quotes.start(task: next.title, seed: seed)
        } else if openTasks.isEmpty {
            quote = Quotes.idle(seed: seed)
        } else {
            quote = "That's all the day we've got. The rest is gonna have to wait."
        }
    }

    // MARK: - Calendar

    func refreshCalendar() {
        if isDemo { return }
        hasCalendarAccess = calendars.hasAccess
        calendarList = calendars.calendars()
        calendarEvents = calendars.events(on: Date(), enabled: settings.enabledCalendarIDs)
        replan()
    }

    func requestCalendarAccess() {
        Task {
            _ = await calendars.requestAccess()
            refreshCalendar()
        }
    }

    func isCalendarOn(_ info: CalendarInfo) -> Bool {
        settings.enabledCalendarIDs?.contains(info.id) ?? info.defaultOn
    }

    func setCalendar(_ info: CalendarInfo, on: Bool) {
        var ids = Set(settings.enabledCalendarIDs ?? calendarList.filter(\.defaultOn).map(\.id))
        if on { ids.insert(info.id) } else { ids.remove(info.id) }
        settings.enabledCalendarIDs = ids.sorted()
        refreshCalendar()
        commit()
    }

    // MARK: - Tasks

    /// Adds a task from quick-add text. `@name` files it under the project whose name starts that way.
    /// - Parameters:
    ///   - project: file it under this project regardless of any `@name`.
    ///   - today: whether a project task also goes on today's list.
    @discardableResult
    func addTask(_ text: String, project: UUID? = nil, today: Bool = true) -> Bool {
        guard let parsed = TaskParser.parseWithProject(text) else { return false }
        var t = parsed.task
        var owner = self.project(project)
        if owner == nil, let word = parsed.project {
            owner = projects.first { $0.name.lowercased().filter { !$0.isWhitespace }.hasPrefix(word) }
            if owner == nil { t.title += " @\(word)" }
        }
        if let owner {
            t.projectID = owner.id
            t.tag = t.tag ?? owner.client
            t.plannedDay = today ? todayKey : nil
        }
        t.order = (tasks.map(\.order).max() ?? 0) + 1
        tasks.append(t)
        commit()
        return true
    }

    func update(_ task: TaskItem) {
        guard let i = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var t = task
        // Filing a task from today's list under a project should not make it vanish from today.
        if t.projectID != nil, t.plannedDay != todayKey, isOnToday(tasks[i]) { t.plannedDay = todayKey }
        if t.projectID == nil { t.plannedDay = nil }
        tasks[i] = t
        commit()
    }

    /// Puts a project task on today's list, or sends it back to the project.
    func setToday(_ id: UUID, _ on: Bool) {
        guard let i = tasks.firstIndex(where: { $0.id == id }), tasks[i].projectID != nil else { return }
        if !on, session?.taskID == id { stop() }
        tasks[i].plannedDay = on ? todayKey : nil
        commit()
    }

    // MARK: - Projects

    func project(_ id: UUID?) -> Project? {
        guard let id else { return nil }
        return projects.first { $0.id == id }
    }

    func addProject(_ project: Project) {
        var p = project
        p.name = p.name.trimmingCharacters(in: .whitespaces)
        guard !p.name.isEmpty else { return }
        projects.append(p)
        commit()
        syncDossiers()
    }

    /// Switches to the projects screen, on one project or on the new-project form.
    func openProjects(select: UUID? = nil, new: Bool = false) {
        draftingProject = new || projects.isEmpty
        if let select { projectSelection = select }
        if project(projectSelection) == nil { projectSelection = projects.first?.id }
        if new { draftSeed = nil }
        showProjects = true
        syncDossiers()
        findStrays()
        // Bring each budgeted project's record of today up to date, unless it was read in the last ten minutes.
        // Projects with no weekly budget are scanned when they are opened.
        for p in projects where (p.isBudgeted || p.id == projectSelection) && p.status == .active && p.folder != nil {
            let last = captures.first { $0.projectID == p.id && $0.day == todayKey }
            if last?.active == nil || now.timeIntervalSince(last?.scannedAt ?? .distantPast) > 600 { scanWork(p.id) }
        }
    }

    // MARK: - Work capture

    /// Every focus block logged against a project, including the one running now.
    func focusWindows(_ id: UUID) -> [DateInterval] {
        var out = log.values.flatMap(\.sessions)
            .filter { $0.projectID == id && $0.kind == .focus && $0.end > $0.start }
            .map { DateInterval(start: $0.start, end: $0.end) }
        if let s = session, s.kind == .focus, !s.isPaused, task(s.taskID)?.projectID == id, now > s.segmentStart {
            out.append(DateInterval(start: s.segmentStart, end: now))
        }
        return out
    }

    /// The stretches of a day's work on a project that no focus block covers.
    func unplanned(_ c: WorkCapture) -> [DateInterval] {
        WorkEvidence.outside(c.active ?? [], windows: focusWindows(c.projectID))
    }

    /// Counts work done off the plan toward the project's hours, as focus time on the day it happened.
    func logUnplanned(_ c: WorkCapture) {
        guard let p = project(c.projectID) else { return }
        for span in unplanned(c) {
            let key = Store.dayKey(span.start)
            log[key, default: DayLog()].focusSeconds += Int(span.duration)
            log[key, default: DayLog()].sessions.append(
                LoggedSession(kind: .focus, title: "\(p.name) (not planned)", taskID: nil, projectID: p.id,
                              start: span.start, end: span.end))
        }
        commit()
    }

    /// Looks on this Mac, and on the other Macs projects name, for today's work outside every project.
    func findStrays() {
        guard !findingStrays else { return }
        findingStrays = true
        let hosts: [String?] = [nil] + Set(projects.compactMap { $0.host?.trimmingCharacters(in: .whitespaces).nilIfEmpty }).sorted()
        let known = Dictionary(grouping: projects.filter { $0.folder != nil }) { $0.host?.trimmingCharacters(in: .whitespaces).nilIfEmpty }
            .mapValues { $0.compactMap(\.folder) }
        let today = now
        Task {
            defer { findingStrays = false }
            var found: [StrayWork] = []
            for host in hosts {
                found += await WorkScanner.strays(host: host, known: known[host] ?? [], today: today)
            }
            strays = found.sorted { $0.minutes > $1.minutes }
        }
    }

    /// Opens the new-project form filled in for a folder that was worked in without a project.
    func adopt(_ stray: StrayWork) {
        draftSeed = Project(name: stray.name, folder: stray.folder, host: stray.host)
        draftingProject = true
        showProjects = true
    }

    func captures(for id: UUID) -> [WorkCapture] {
        captures.filter { $0.projectID == id }.sorted { $0.day > $1.day }
    }

    /// Reads the project's folder for the last week of commits and Claude Code sessions.
    func scanWork(_ id: UUID) {
        guard let p = project(id), let folder = p.folder, !folder.isEmpty, !scanning.contains(id) else { return }
        scanning.insert(id)
        scanErrors[id] = nil
        let windows = focusWindows(id)
        let today = now
        Task {
            defer { scanning.remove(id) }
            do {
                let found = try await WorkScanner.scan(projectID: id, name: p.name, folder: folder, host: p.host,
                                                       windows: windows, today: today)
                let days = Set(found.map(\.day))
                let old = captures.filter { $0.projectID == id && days.contains($0.day) }
                captures.removeAll { $0.projectID == id && days.contains($0.day) }
                captures += found.map { c in
                    var c = c
                    c.summary = old.first { $0.day == c.day }?.summary
                    return c
                }
                let cutoff = Store.dayKey(today.addingTimeInterval(-90 * 86_400))
                captures.removeAll { $0.day < cutoff }
                commit()
                writeDossier(id)
            } catch {
                scanErrors[id] = error.localizedDescription
            }
        }
    }

    /// Asks Claude to turn one day's evidence into a short account of what got done.
    func writeUp(_ capture: WorkCapture) {
        guard let p = project(capture.projectID), !writingUp.contains(capture.id) else { return }
        writingUp.insert(capture.id)
        scanErrors[p.id] = nil
        var bare = capture
        bare.summary = nil
        let evidence = WorkEvidence.digest(bare, project: p.name) { Fmt.timeAMPM.string(from: $0) }
        let model = settings.model
        Task {
            defer { writingUp.remove(capture.id) }
            do {
                let text = try await ClaudeCode.text(prompt: WorkScanner.writeUpPrompt(evidence: evidence), model: model)
                if let i = captures.firstIndex(where: { $0.id == capture.id }) {
                    captures[i].summary = text
                    commit()
                    writeDossier(p.id)
                }
            } catch {
                scanErrors[p.id] = error.localizedDescription
            }
        }
    }

    func updateProject(_ project: Project) {
        guard let i = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[i] = project
        commit()
        writeDossier(project.id)
    }

    /// Removes the project and its unfinished tasks. Time already logged keeps its project label.
    func deleteProject(_ id: UUID) {
        retireDossier(id)
        if task(session?.taskID)?.projectID == id { stop() }
        tasks.removeAll { $0.projectID == id }
        projects.removeAll { $0.id == id }
        captures.removeAll { $0.projectID == id }
        if projectSelection == id { projectSelection = projects.first?.id }
        commit()
    }

    func tasks(in project: UUID) -> [TaskItem] {
        tasks.filter { $0.projectID == project && $0.isBlock != true }
    }

    /// Focus minutes logged on a project since the start of this week, including the running timer.
    func loggedThisWeek(_ id: UUID) -> Int {
        let cal = Calendar.current
        guard let week = cal.dateInterval(of: .weekOfYear, for: now) else { return 0 }
        var seconds = 0.0
        var day = week.start
        while day < week.end {
            for s in log[Store.dayKey(day)]?.sessions ?? [] where s.projectID == id && s.kind == .focus {
                seconds += s.end.timeIntervalSince(s.start)
            }
            day = cal.date(byAdding: .day, value: 1, to: day) ?? week.end
        }
        if let s = session, s.kind == .focus, !s.isPaused, task(s.taskID)?.projectID == id {
            seconds += max(0, minuteNow.timeIntervalSince(s.segmentStart))
        }
        return Int(seconds / 60)
    }

    /// Works out what to pull from the projects into today's open time, and shows it for approval.
    func planMyDay() {
        replan()
        let loads = projects.map { p in
            ProjectLoad(
                project: p,
                loggedMinutes: loggedThisWeek(p.id),
                plannedMinutes: tasks.filter { $0.projectID == p.id && !$0.isDone && isOnToday($0) }
                    .reduce(0) { $0 + $1.remainingMinutes },
                candidates: Planner.queue(tasks(in: p.id).filter { !isOnToday($0) }))
        }
        proposal = ProjectPlanner.propose(loads: loads, freeMinutes: openFocusMinutes, today: now)
    }

    /// Focus time still unclaimed today. Measured by asking the planner how much one endless task
    /// would get, so breaks and gaps too short to use are already taken out.
    var openFocusMinutes: Int {
        let endless = TaskItem(title: "", estimateMinutes: 24 * 60)
        let notBefore = session.map { now.addingTimeInterval($0.remaining(at: now)) }
        let capacity = Planner.plan(now: now, events: agenda, tasks: [endless], settings: settings.planner,
                                    cyclesDone: todayLog.pomodoros, notBefore: notBefore)
            .focusBlocks.reduce(0) { $0 + $1.minutes }
        return max(0, capacity - plan.demandMinutes)
    }

    func accept(_ lines: [Proposal.Line]) {
        for line in lines {
            if let id = line.taskID {
                if let i = tasks.firstIndex(where: { $0.id == id }) { tasks[i].plannedDay = todayKey }
            } else if let p = project(line.projectID) {
                tasks.append(TaskItem(title: line.title, estimateMinutes: line.minutes, priority: p.priority,
                                      tag: p.client, order: (tasks.map(\.order).max() ?? 0) + 1,
                                      projectID: p.id, plannedDay: todayKey, isBlock: true))
            }
        }
        proposal = nil
        sideTab = .today
        commit()
    }

    func delete(_ id: UUID) {
        if session?.taskID == id { stop() }
        tasks.removeAll { $0.id == id }
        commit()
    }

    func moveToTop(_ id: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].order = (tasks.map(\.order).min() ?? 0) - 1
        commit()
    }

    func setDone(_ id: UUID, _ done: Bool) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        if done, session?.taskID == id, session?.kind == .focus {
            credit(until: Date())
            session = nil
        }
        tasks[i].isDone = done
        tasks[i].doneAt = done ? Date() : nil
        if done {
            log[todayKey, default: DayLog()].completedTasks.append(tasks[i].title)
            play("Glass")
        } else {
            log[todayKey]?.completedTasks.removeAll { $0 == tasks[i].title }
        }
        commit()
    }

    /// Finished project tasks stay in their project as a record; loose ones and time blocks go.
    func clearCompleted() {
        tasks.removeAll { $0.isDone && ($0.projectID == nil || $0.isBlock == true) }
        commit()
    }

    // MARK: - Calendar photos

    /// Replaces photo events on every date the new import covers.
    func importPhotoEvents(_ events: [ImportedEvent]) {
        let days = Set(events.map { Store.dayKey($0.start) })
        photoEvents.removeAll { days.contains(Store.dayKey($0.start)) }
        photoEvents.append(contentsOf: events)
        // Drop anything more than two weeks old.
        let cutoff = Date().addingTimeInterval(-14 * 86_400)
        photoEvents.removeAll { $0.end < cutoff }
        commit()
    }

    func clearPhotoEvents() {
        photoEvents.removeAll()
        commit()
    }

    // MARK: - Timer

    /// Seconds for a focus block starting now: the usual length, shortened to stop before the next meeting.
    private func focusLength() -> Double {
        let p = settings.planner
        guard let m = nextMeeting else { return Double(p.focusMinutes) * 60 }
        let room = m.start.timeIntervalSince(now) - Double(p.meetingBufferMinutes) * 60
        if room >= Double(p.minFocusMinutes) * 60 { return min(Double(p.focusMinutes) * 60, room) }
        return Double(p.focusMinutes) * 60
    }

    func startFocus(_ task: TaskItem?) {
        now = Date()
        if session != nil { credit(until: now) }
        let length = focusLength()
        session = Session(kind: .focus, taskID: task?.id, title: task?.title ?? "Open focus",
                          segmentStart: now, endsAt: now.addingTimeInterval(length), total: length)
        snoozeUntil = nil
        nags.dismiss()
        commit()
    }

    /// Moves the timer to another project without resetting the clock. The time so far stays
    /// with the project it was spent on. With nothing running, starts a focus block on it.
    func switchTo(_ id: UUID) {
        guard let p = project(id) else { return }
        now = Date()
        var target = openTasks.first { $0.projectID == id && $0.remainingMinutes > 0 }
            ?? openTasks.first { $0.projectID == id }
        if target == nil {
            let block = TaskItem(title: "Work on \(p.name)", estimateMinutes: settings.planner.focusMinutes,
                                 priority: p.priority, tag: p.client, order: (tasks.map(\.order).max() ?? 0) + 1,
                                 projectID: p.id, plannedDay: todayKey, isBlock: true)
            tasks.append(block)
            target = block
        }
        guard let target else { return }
        guard var s = session, s.kind == .focus else {
            startFocus(target)
            return
        }
        guard s.taskID != target.id else { return }
        credit(until: now)
        s.taskID = target.id
        s.title = target.title
        if !s.isPaused { s.segmentStart = now }
        session = s
        nags.dismiss()
        commit()
    }

    // MARK: - Dossiers

    /// A demo without its own storage folder leaves the real dossiers alone.
    private var dossiersOn: Bool {
        !isDemo || !(ProcessInfo.processInfo.environment["LUMBERG_HOME"] ?? "").isEmpty
    }

    /// Reads the dossier folder. A dossier nobody has yet becomes a project; a dossier that was edited
    /// outside Lumberg updates its project; a project with no dossier gets one written.
    func syncDossiers() {
        guard dossiersOn else { return }
        var changed = false
        var linked = Set(projects.compactMap(\.dossier))
        for (slug, dossier) in DossierStore.all() where dossier.isTracked {
            let index = projects.firstIndex { $0.dossier == slug }
                ?? projects.firstIndex { p in
                    guard p.dossier == nil, let name = dossier["name"] else { return false }
                    return p.name.caseInsensitiveCompare(name) == .orderedSame
                        || (p.folder != nil && p.folder == dossier["folder"] && p.host?.nilIfEmpty == dossier["host"])
                }
            var p = index.map { projects[$0] } ?? Project(name: dossier["name"] ?? slug, weeklyTargetMinutes: 0)
            let before = p
            dossier.apply(to: &p)
            p.dossier = slug
            linked.insert(slug)
            guard p != before || index == nil else { continue }
            if let index { projects[index] = p } else { projects.append(p) }
            changed = true
        }
        for i in projects.indices where projects[i].dossier == nil || DossierStore.read(projects[i].dossier!) == nil {
            // A project made in the app, or one whose file was deleted: write it a dossier.
            let slug = projects[i].dossier ?? DossierStore.freeSlug(for: projects[i].name, taken: linked)
            linked.insert(slug)
            projects[i].dossier = slug
            DossierStore.write(slug, Dossier.template(for: projects[i], slug: slug, day: todayKey))
            changed = true
        }
        if changed { commit() }
        for p in projects { writeDossier(p.id) }
        if project(projectSelection) == nil { projectSelection = projects.first?.id }
    }

    /// Brings one project's dossier up to date: its settings in the header, and the block of what Lumberg tracks.
    func writeDossier(_ id: UUID) {
        guard dossiersOn, let p = project(id), let slug = p.dossier, var d = DossierStore.read(slug),
              d["status"]?.lowercased() != Dossier.removed else { return }
        d.take(from: p, slug: slug)
        d.setAuto(trackedBlock(p))
        let was = DossierStore.read(slug)
        if was != d {
            d["updated"] = todayKey
            DossierStore.write(slug, d)
        }
    }

    private func trackedBlock(_ p: Project) -> String {
        let cal = Calendar.current
        let week = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let monthAgo = Store.dayKey(now.addingTimeInterval(-27 * 86_400))
        var four = 0.0
        var last: String?
        for (day, entry) in log where day >= monthAgo {
            for s in entry.sessions where s.projectID == p.id && s.kind == .focus {
                four += s.end.timeIntervalSince(s.start)
                if day > (last ?? "") { last = day }
            }
        }
        if last == nil {
            last = log.filter { $0.value.sessions.contains { $0.projectID == p.id && $0.kind == .focus } }.keys.max()
        }
        let days = captures(for: p.id).map { c in
            Dossier.TrackedDay(day: c.day, workedMinutes: WorkEvidence.minutes(c.active ?? []), commits: c.commits.count,
                               requests: c.prompts.count, summary: c.summary)
        }
        // Whole minutes logged in finished blocks only, so the file does not change every minute a timer runs.
        var weekSeconds = 0.0
        var day = week
        while day <= now {
            for s in log[Store.dayKey(day)]?.sessions ?? [] where s.projectID == p.id && s.kind == .focus {
                weekSeconds += s.end.timeIntervalSince(s.start)
            }
            day = cal.date(byAdding: .day, value: 1, to: day) ?? now.addingTimeInterval(1)
        }
        return Dossier.tracked(project: p, weekOf: Store.dayKey(week), weekMinutes: Int(weekSeconds / 60),
                               fourWeekMinutes: Int(four / 60), lastFocus: last,
                               openTasks: Planner.queue(tasks(in: p.id)).map(\.title), days: days)
    }

    /// Reads the project's folder again if today's record is missing or more than ten minutes old.
    func scanIfStale(_ id: UUID) {
        guard let p = project(id), p.status == .active, p.folder != nil else { return }
        let last = captures.first { $0.projectID == id && $0.day == todayKey }
        if last?.active == nil || now.timeIntervalSince(last?.scannedAt ?? .distantPast) > 600 { scanWork(id) }
    }

    /// Adds a dated line to the project's dossier log.
    func addDossierNote(_ id: UUID, _ text: String) {
        guard dossiersOn, let slug = project(id)?.dossier, var d = DossierStore.read(slug) else { return }
        d.appendLog(text, day: todayKey)
        d["updated"] = todayKey
        DossierStore.write(slug, d)
        dossierStamp += 1
    }

    /// Marks a deleted project's dossier so it is not picked up again. The file itself stays.
    private func retireDossier(_ id: UUID) {
        guard dossiersOn, let slug = project(id)?.dossier, var d = DossierStore.read(slug) else { return }
        d["status"] = Dossier.removed
        d.appendLog("Removed from Lumberg. Set status back to active in the header to bring it back.", day: todayKey)
        d["updated"] = todayKey
        DossierStore.write(slug, d)
    }

    func dossier(_ id: UUID) -> Dossier? {
        _ = dossierStamp
        guard dossiersOn, let slug = project(id)?.dossier else { return nil }
        return DossierStore.read(slug)
    }

    /// The project the running focus block is counted against.
    var currentProject: UUID? {
        guard let s = session, s.kind == .focus else { return nil }
        return task(s.taskID)?.projectID
    }

    /// Every few minutes during a focus block, looks at where requests are being typed to Claude Code.
    /// If that is another project's folder, offers to move the timer there.
    private func checkDrift() {
        guard let s = session, s.kind == .focus, !s.isPaused, !checkingDrift, !nags.isShowing,
              now.timeIntervalSince(lastDriftCheck) >= 170, now.timeIntervalSince(lastDriftNag) >= 600 else { return }
        let foldered = projects.filter { $0.status == .active && $0.folder != nil }
        guard !foldered.isEmpty else { return }
        lastDriftCheck = now
        checkingDrift = true
        let clean = { (h: String?) in h?.trimmingCharacters(in: .whitespaces).nilIfEmpty }
        let hosts: [String?] = [nil] + Set(foldered.compactMap { clean($0.host) }).sorted()
        Task {
            defer { checkingDrift = false }
            var best: (project: Project, date: Date)?
            for host in hosts {
                guard let typed = await WorkScanner.lastTyped(host: host) else { continue }
                let owner = foldered.first { p in
                    guard clean(p.host) == host, let f = p.folder else { return false }
                    let folder = f == "~" ? typed.home : f.hasPrefix("~/") ? typed.home + String(f.dropFirst(1)) : f
                    return WorkEvidence.isInside(typed.cwd, folder)
                }
                if let owner, typed.date > (best?.date ?? .distantPast) { best = (owner, typed.date) }
            }
            guard let best, let live = session, live.kind == .focus, !live.isPaused, !nags.isShowing,
                  best.project.id != currentProject,
                  best.date > live.segmentStart, Date().timeIntervalSince(best.date) < 600,
                  (driftQuiet[best.project.id] ?? .distantPast) < Date() else { return }
            lastDriftNag = Date()
            let id = best.project.id
            show(Nag(mood: .neutral, title: "SWITCHED GEARS?",
                     message: "Yeah, it looks like you're working on \(best.project.name). The timer says \(live.title).",
                     actions: [
                        NagAction(title: "Stay", primary: false) { [weak self] in
                            self?.driftQuiet[id] = Date().addingTimeInterval(30 * 60)
                        },
                        NagAction(title: "Switch to \(best.project.name)", primary: true) { [weak self] in
                            self?.switchTo(id)
                        },
                     ]), sound: "Ping")
        }
    }

    /// Start whatever the plan says is next.
    func startNext() {
        if let next = nextFocus, let t = task(next.taskID) {
            startFocus(t)
        } else {
            startFocus(openTasks.first)
        }
    }

    func startBreak(long: Bool) {
        now = Date()
        if session != nil { credit(until: now) }
        let p = settings.planner
        let length = Double(long ? p.longBreakMinutes : p.shortBreakMinutes) * 60
        session = Session(kind: long ? .longBreak : .shortBreak, taskID: nil, title: long ? "Long break" : "Break",
                          segmentStart: now, endsAt: now.addingTimeInterval(length), total: length)
        commit()
    }

    /// A break asked for mid-task. Time worked so far is credited; the block does not count as finished.
    func needBreak() {
        let wasFocus = session?.kind == .focus
        startBreak(long: false)
        nags.dismiss()
        if wasFocus { play("Pop") }
    }

    func togglePause() {
        guard var s = session else { return }
        now = Date()
        if let left = s.pausedRemaining {
            s.pausedRemaining = nil
            s.segmentStart = now
            s.endsAt = now.addingTimeInterval(left)
            session = s
        } else {
            credit(until: now)
            s.pausedRemaining = s.remaining(at: now)
            session = s
        }
        commit()
    }

    func extend(minutes: Int) {
        guard var s = session else { return }
        let add = Double(minutes) * 60
        if let left = s.pausedRemaining { s.pausedRemaining = left + add } else { s.endsAt += add }
        s.total += add
        session = s
        commit()
    }

    func stop() {
        guard session != nil else { return }
        credit(until: Date())
        session = nil
        lastNag = Date()
        commit()
    }

    /// Adds the time since the current segment began to the task and the day's log.
    private func credit(until: Date) {
        guard let s = session, !s.isPaused else { return }
        let end = min(until, s.endsAt)
        let seconds = Int(end.timeIntervalSince(s.segmentStart))
        guard seconds > 0 else { return }
        let key = Store.dayKey(s.segmentStart)
        if s.kind == .focus {
            if let i = tasks.firstIndex(where: { $0.id == s.taskID }) { tasks[i].spentSeconds += seconds }
            log[key, default: DayLog()].focusSeconds += seconds
        }
        if seconds >= 60 {
            let owner = task(s.taskID)?.projectID
            log[key, default: DayLog()].sessions.append(
                LoggedSession(kind: s.kind, title: s.title, taskID: s.taskID,
                              projectID: owner, start: s.segmentStart, end: end))
            // A finished stretch of project work: see what the folder says got done.
            if s.kind == .focus, let owner, project(owner)?.folder != nil {
                DispatchQueue.main.async { [weak self] in self?.scanWork(owner) }
            }
        }
    }

    private func finishSession() {
        guard let s = session else { return }
        credit(until: s.endsAt)
        session = nil
        let seed = Int(now.timeIntervalSinceReferenceDate)

        if s.kind == .focus {
            log[todayKey, default: DayLog()].pomodoros += 1
            let long = todayLog.pomodoros % max(settings.planner.cyclesBeforeLongBreak, 1) == 0
            if settings.autoStartBreaks { startBreak(long: long) }
            var actions: [NagAction] = []
            if let t = task(s.taskID) {
                actions.append(NagAction(title: "It's done", primary: false) { [weak self] in self?.setDone(t.id, true) })
                actions.append(NagAction(title: "Keep going", primary: false) { [weak self] in
                    guard let self else { return }
                    self.startFocus(self.task(t.id))
                })
            }
            actions.append(NagAction(title: "Take the break", primary: true) { [weak self] in
                guard let self, self.session == nil else { return }
                self.startBreak(long: long)
            })
            show(Nag(mood: .pleased, title: long ? "LONG BREAK" : "BREAK",
                     message: Quotes.focusDone(task: s.title, seed: seed), actions: actions), sound: "Glass")
        } else {
            lastNag = now
            commit()
            let next = nextFocus
            var actions: [NagAction] = []
            if next != nil {
                actions.append(NagAction(title: "Snooze 5", primary: false) { [weak self] in self?.snooze(5) })
                actions.append(NagAction(title: "Start", primary: true) { [weak self] in self?.startNext() })
            } else {
                actions.append(NagAction(title: "OK", primary: true) {})
            }
            show(Nag(mood: .neutral, title: "BACK TO WORK",
                     message: Quotes.breakOver(next: next?.title, seed: seed), actions: actions), sound: "Ping")
        }
        commit()
    }

    // MARK: - Nagging

    func snooze(_ minutes: Int) {
        snoozeUntil = Date().addingTimeInterval(Double(minutes) * 60)
    }

    private func show(_ nag: Nag, sound: String) {
        nags.show(nag)
        play(sound)
    }

    private func play(_ name: String) {
        if settings.soundsOn { NSSound(named: name)?.play() }
    }

    private func checkIdle() {
        guard session == nil, !nags.isShowing, inWorkHours, currentMeeting == nil else { return }
        if let snoozeUntil, now < snoozeUntil { return }
        guard now.timeIntervalSince(lastNag) >= Double(settings.nagIntervalMinutes) * 60 else { return }
        guard let next = nextFocus, next.start.timeIntervalSince(now) <= 5 * 60 else { return }
        lastNag = now
        show(Nag(mood: .displeased, title: "WHAT'S HAPPENING",
                 message: Quotes.start(task: next.title, seed: Int(now.timeIntervalSinceReferenceDate)),
                 actions: [
                    NagAction(title: "Snooze 5", primary: false) { [weak self] in self?.snooze(5) },
                    NagAction(title: "Start", primary: true) { [weak self] in self?.startNext() },
                 ]), sound: "Funk")
    }

    private func checkMeetings() {
        let lead = Double(settings.meetingLeadMinutes) * 60
        for e in agenda where !e.isAllDay {
            let until = e.start.timeIntervalSince(now)
            if until > 0, until <= lead + 30, !warned.contains(e.id) {
                warned.insert(e.id)
                let minutes = max(1, Int((until / 60).rounded()))
                show(Nag(mood: .neutral, title: "MEETING",
                         message: Quotes.meetingSoon(title: e.title, minutes: minutes, seed: Int(e.start.timeIntervalSinceReferenceDate)),
                         actions: [NagAction(title: "Mmmkay", primary: true) {}]), sound: "Submarine")
            } else if until <= 0, until > -90, !warned.contains(e.id + "-now") {
                warned.insert(e.id + "-now")
                warned.insert(e.id)
                if let s = session, s.kind == .focus, !s.isPaused {
                    togglePause()
                    show(Nag(mood: .neutral, title: "MEETING NOW", message: Quotes.meetingNow(title: e.title),
                             actions: [NagAction(title: "Mmmkay", primary: true) {}]), sound: "Submarine")
                }
            }
        }
    }

    private func checkEndOfDay() {
        let end = Planner.workWindow(for: now, settings: settings.planner).end
        let since = now.timeIntervalSince(end)
        guard since >= 0, since < 600, closedDay != todayKey, session == nil else { return }
        closedDay = todayKey
        let l = todayLog
        show(Nag(mood: l.pomodoros > 0 ? .pleased : .displeased, title: "END OF DAY",
                 message: Quotes.endOfDay(pomodoros: l.pomodoros, minutes: l.focusSeconds / 60),
                 actions: [
                    NagAction(title: "Dismiss", primary: false) {},
                    NagAction(title: "TPS report", primary: true) { [weak self] in
                        self?.showReport = true
                        self?.showMain()
                    },
                 ]), sound: "Glass")
    }

    // MARK: - Demo

    /// Sample day for screenshots: `--demo` with LUMBERG_HOME pointed somewhere disposable.
    private func seedDemo() {
        let cal = Calendar.current
        let day = cal.startOfDay(for: Date())
        func at(_ h: Int, _ m: Int = 0) -> Date { day.addingTimeInterval(Double(h * 60 + m) * 60) }
        settings.planner.workStart = 7 * 60
        settings.planner.workEnd = 19 * 60
        let hour = cal.component(.hour, from: Date())
        calendarEvents = [
            AgendaEvent(id: "d1", title: "Team standup", start: at(hour + 1), end: at(hour + 1, 30), source: "Work", colorHex: "#7FA7C9"),
            AgendaEvent(id: "d2", title: "Pipeline review", start: at(hour + 3), end: at(hour + 4), source: "Client", colorHex: "#9CCB8A"),
        ]
        hasCalendarAccess = true
        if projects.isEmpty {
            let rubric = Project(name: "Scoring rubric", client: WorkTag("work"), weeklyTargetMinutes: 360, priority: 1)
            var portal = Project(name: "Client portal", client: WorkTag("client"), weeklyTargetMinutes: 480)
            let side = Project(name: "Side project", client: WorkTag("personal"), weeklyTargetMinutes: 240, priority: 3)
            // Point the demo at a real folder to see captured work.
            portal.folder = ProcessInfo.processInfo.environment["LUMBERG_DEMO_FOLDER"]
            projects = [rubric, portal, side]
            for (line, p) in [("Revise scoring bands 60m", rubric), ("Calendar macro fixes 45m !1", rubric),
                              ("WBS comments view 90m", portal), ("Invoice export 50m", portal)] {
                if var t = TaskParser.parse(line) {
                    t.projectID = p.id
                    t.tag = p.client
                    t.order = Double(100 + tasks.count)
                    tasks.append(t)
                }
            }
        }
        if tasks.allSatisfy({ $0.projectID != nil }) {
            photoEvents = [ImportedEvent(title: "Calibration sync", start: at(hour + 2), end: at(hour + 2, 45), location: "Teams")]
            for line in ["TPS report cover sheets 50m !1 #work", "Ship portal update 75m #client",
                         "Review pull request 25m #me", "Reply to Dana 15m !1 #work", "Plan Q1 roadmap 2h !3 #me"] {
                if var t = TaskParser.parse(line) {
                    t.order = Double(tasks.count)
                    tasks.append(t)
                }
            }
        }
    }

    // MARK: - Windows

    /// Brings the full window back and puts the small box away.
    func showMain() {
        mini.hide()
        mainWindow?.deminiaturize(nil)
        openMain?()
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Called once the main window exists: the small box takes over whenever it is minimized or closed.
    func attach(_ window: NSWindow) {
        guard mainWindow !== window else { return }
        mainWindow = window
        // macOS can bring the window back already minimized.
        if window.isMiniaturized { mini.show(state: self) }
        let center = NotificationCenter.default
        for name in [NSWindow.didMiniaturizeNotification, NSWindow.willCloseNotification] {
            center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.mini.show(state: self)
                }
            }
        }
        for name in [NSWindow.didDeminiaturizeNotification, NSWindow.didBecomeMainNotification] {
            center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.mini.hide() }
            }
        }
    }
}
