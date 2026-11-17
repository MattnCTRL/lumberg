import LumbergCore
import SwiftUI

/// The full-window projects screen: the list on the left, one project (or the new-project form) on the right.
struct ProjectsScreen: View {
    @Environment(AppState.self) private var state

    private var sorted: [Project] {
        state.projects.sorted {
            if ($0.status == .active) != ($1.status == .active) { return $0.status == .active }
            if $0.isBudgeted != $1.isBudgeted { return $0.isBudgeted }
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            if $0.isBudgeted { return $0.createdAt < $1.createdAt }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            list
                .frame(width: 320)
                .background(Theme.panel)
            Divider().overlay(Theme.line)
            Group {
                if state.draftingProject {
                    NewProjectForm()
                        .id(state.draftSeed?.id)
                } else if let p = state.project(state.projectSelection) {
                    ProjectDetail(project: p)
                        .id(p.id)
                } else {
                    VStack(spacing: 12) {
                        Text("No project selected")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Pick one on the left, or make a new one.")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.dim)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg.opacity(0.94))
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionLabel("PROJECTS")
                Spacer()
                Text("\(state.projects.filter(\.isBudgeted).count) BUDGETED · \(state.projects.filter { $0.status == .active }.count) ACTIVE")
                    .font(Theme.mono(10.5, .medium))
                    .foregroundStyle(Theme.dim)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            Button {
                state.draftSeed = nil
                state.draftingProject = true
            } label: {
                Label("New project", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PillButton(filled: true))
            .keyboardShortcut("n", modifiers: .command)
            .tip("Start a new project (⌘N)")
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .zIndex(1)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(sorted) { p in
                        row(p)
                    }
                    notBudgeted
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
    }

    /// Today's work in folders that belong to no project.
    @ViewBuilder private var notBudgeted: some View {
        HStack {
            SectionLabel("NOT BUDGETED TODAY")
            Spacer()
            if state.findingStrays { ProgressView().controlSize(.small) }
            Button("Check") { state.findStrays() }
                .buttonStyle(PillButton())
                .disabled(state.findingStrays)
                .tip("Look for Claude Code work today in folders that are not a project", align: .trailing)
        }
        .padding(.horizontal, 6)
        .padding(.top, 18)
        .zIndex(1)
        if state.strays.isEmpty {
            Text(state.findingStrays ? "Looking…" : "Nothing today outside your projects.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.dim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
        }
        ForEach(state.strays) { stray in
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(stray.name)
                        .font(.system(size: 13.5, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text("ABOUT \(Quotes.format(stray.minutes).uppercased())")
                        .font(Theme.mono(10, .bold))
                        .foregroundStyle(Theme.amber)
                }
                Text(Self.when(stray))
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
                Button("Make it a project") { state.adopt(stray) }
                    .buttonStyle(PillButton())
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.raised.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private static func when(_ stray: StrayWork) -> String {
        guard let first = stray.spans.first, let last = stray.spans.last else { return "" }
        return "\(Fmt.range(first.start, last.end)) · \(stray.host ?? "this Mac")"
    }

    private func row(_ p: Project) -> some View {
        let on = !state.draftingProject && state.projectSelection == p.id
        let logged = state.loggedThisWeek(p.id)
        let color = Theme.color(for: p.client)
        return Button {
            state.draftingProject = false
            state.projectSelection = p.id
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(p.name)
                        .font(.system(size: 13.5, weight: .semibold))
                        .lineLimit(1)
                    if p.priority == 1 { Text("!1").font(Theme.mono(10, .bold)).foregroundStyle(Theme.red) }
                    Spacer(minLength: 0)
                    if p.status != .active {
                        Text(p.status.label.uppercased()).font(Theme.mono(9, .bold)).foregroundStyle(Theme.amber)
                    }
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.line)
                        Capsule().fill(color)
                            .frame(width: geo.size.width * min(1, CGFloat(logged) / CGFloat(max(p.weeklyTargetMinutes, 1))))
                    }
                }
                .frame(height: 4)
                HStack(spacing: 6) {
                    if let client = p.client {
                        Text(client.short).font(Theme.mono(10, .bold)).foregroundStyle(color)
                    }
                    Text("\(Quotes.format(logged)) of \(Quotes.format(p.weeklyTargetMinutes)) this week")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.dim)
                }
            }
            .padding(10)
            .background(on ? Theme.raised : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(on ? Theme.paper.opacity(0.25) : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
            .opacity(p.status == .active ? 1 : 0.6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Fields

/// The fields a project has, used both for a new one and for editing.
struct ProjectFields: View {
    @Binding var project: Project
    @FocusState private var nameFocused: Bool
    var focusName = false

    private enum Place: String { case here, remote }

    private var place: Binding<Place> {
        Binding {
            project.host == nil ? .here : .remote
        } set: { value in
            project.host = value == .here ? nil : (project.host ?? "")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            field("NAME") {
                TextField("What is this project called?", text: $project.name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .semibold))
                    .padding(10)
                    .background(Theme.raised, in: RoundedRectangle(cornerRadius: 8))
                    .focused($nameFocused)
            }

            HStack(alignment: .top, spacing: 20) {
                field("WHO IT IS FOR") {
                    Picker("", selection: $project.client) {
                        Text("Nobody").tag(WorkTag?.none)
                        ForEach(WorkTag.allCases) { Text($0.label).tag(WorkTag?.some($0)) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                field("PRIORITY") {
                    Picker("", selection: $project.priority) {
                        Text("High").tag(1)
                        Text("Normal").tag(2)
                        Text("Low").tag(3)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 210)
                }
            }

            HStack(alignment: .top, spacing: 20) {
                field("HOURS A WEEK") {
                    HStack(spacing: 10) {
                        Text(Quotes.format(project.weeklyTargetMinutes))
                            .font(Theme.mono(15, .bold))
                            .frame(width: 70, alignment: .leading)
                        Stepper("", value: $project.weeklyTargetMinutes, in: 30...3000, step: 30)
                            .labelsHidden()
                    }
                    Text("Plan my day spreads what is left of this over the rest of the week.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.dim)
                }
                field("DEADLINE") {
                    HStack(spacing: 10) {
                        Toggle("", isOn: Binding(
                            get: { project.deadline != nil },
                            set: { project.deadline = $0 ? Date().addingTimeInterval(7 * 86_400) : nil }))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        if project.deadline != nil {
                            DatePicker("", selection: Binding(get: { project.deadline ?? Date() },
                                                              set: { project.deadline = $0 }),
                                       displayedComponents: .date)
                                .labelsHidden()
                        } else {
                            Text("None").font(.system(size: 13)).foregroundStyle(Theme.dim)
                        }
                    }
                }
            }

            field("PROJECT FOLDER (OPTIONAL)") {
                Picker("", selection: place) {
                    Text("This Mac or a plugged-in drive").tag(Place.here)
                    Text("Another Mac").tag(Place.remote)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 380)

                if project.host == nil {
                    HStack(spacing: 8) {
                        Text(project.folder ?? "No folder chosen")
                            .font(Theme.mono(11.5))
                            .foregroundStyle(project.folder == nil ? Theme.dim : Theme.paper)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 7))
                        Button("Choose…") { choose() }
                            .buttonStyle(PillButton())
                        if project.folder != nil {
                            Button("Clear") { project.folder = nil }
                                .buttonStyle(PillButton())
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        TextField("Mac name, e.g. studio", text: Binding(get: { project.host ?? "" },
                                                                        set: { project.host = $0 }))
                            .textFieldStyle(.plain)
                            .font(Theme.mono(12))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .frame(width: 170)
                            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 7))
                        TextField("Folder on that Mac, e.g. ~/code/portal",
                                  text: Binding(get: { project.folder ?? "" },
                                                set: { project.folder = $0.isEmpty ? nil : $0 }))
                            .textFieldStyle(.plain)
                            .font(Theme.mono(12))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 7))
                    }
                }
                Text(project.host == nil
                     ? "Lumberg reads this folder's git commits, Claude Code sessions, dated session notes and changed file names to record what got done during your focus time. It never writes to the folder. A folder on a drive is read whenever the drive is plugged in."
                     : "Read over SSH, using the name you would type after ssh. Nothing is changed on the other Mac.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { if focusName { nameFocused = true } }
    }

    private func field(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(title)
            content()
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose the folder this project's work lives in"
        panel.prompt = "Choose"
        if let folder = project.folder { panel.directoryURL = URL(fileURLWithPath: folder) }
        if panel.runModal() == .OK, let url = panel.url { project.folder = url.path }
    }
}

struct NewProjectForm: View {
    @Environment(AppState.self) private var state
    @State private var draft = Project(name: "")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NEW PROJECT")
                        .font(Theme.mono(15, .heavy))
                        .tracking(3)
                    Text("Only the name is needed. Everything else can be changed later.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.dim)
                }
                ProjectFields(project: $draft, focusName: true)
                    .onAppear { if let seed = state.draftSeed { draft = seed } }
                HStack(spacing: 10) {
                    Button("Create project") { create() }
                        .buttonStyle(PillButton(filled: true))
                        .keyboardShortcut(.defaultAction)
                        .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                    if !state.projects.isEmpty {
                        Button("Cancel") {
                            state.draftingProject = false
                            state.draftSeed = nil
                        }
                            .buttonStyle(PillButton())
                            .keyboardShortcut(.cancelAction)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func create() {
        var p = draft
        if p.host?.trimmingCharacters(in: .whitespaces).isEmpty == true || p.folder == nil { p.host = nil }
        state.addProject(p)
        state.projectSelection = p.id
        state.draftingProject = false
        if p.folder != nil { state.scanWork(p.id) }
        state.draftSeed = nil
        state.findStrays()
        draft = Project(name: "")
    }
}

// MARK: - One project

struct ProjectDetail: View {
    @Environment(AppState.self) private var state
    let project: Project
    @State private var taskDraft = ""
    @State private var confirmDelete = false

    private var binding: Binding<Project> {
        Binding {
            state.project(project.id) ?? project
        } set: { value in
            guard !value.name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            state.updateProject(value)
        }
    }

    var body: some View {
        let all = state.tasks(in: project.id)
        let open = Planner.queue(all)
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(spacing: 10) {
                    Text("\(Quotes.format(state.loggedThisWeek(project.id))) of \(Quotes.format(project.weeklyTargetMinutes)) this week · \(open.count) open task\(open.count == 1 ? "" : "s")")
                        .font(Theme.mono(11.5, .medium))
                        .foregroundStyle(Theme.dim)
                    Spacer()
                    Picker("", selection: binding.status) {
                        ForEach(ProjectStatus.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 210)
                    .tip("Paused and done projects are left out of Plan my day")
                    Button { confirmDelete = true } label: {
                        Image(systemName: "trash").font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(IconButton(size: 28, tint: Theme.red))
                    .tip("Delete this project", align: .trailing)
                    .accessibilityLabel("Delete \(project.name)")
                }
                .zIndex(2)

                ProjectFields(project: binding)

                DossierSection(project: project)

                tasks(open: open, done: all.filter(\.isDone).count)

                WorkCaptured(project: project)
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .confirmationDialog("Delete \(project.name)?", isPresented: $confirmDelete) {
            Button("Delete project and its tasks", role: .destructive) { state.deleteProject(project.id) }
        } message: {
            Text("Its tasks and captured work are removed. Time already logged stays in your reports.")
        }
    }

    private func tasks(open: [TaskItem], done: Int) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                SectionLabel("TASKS")
                Spacer()
                if done > 0 {
                    Text("\(done) finished").font(Theme.mono(10)).foregroundStyle(Theme.faint)
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.dim)
                TextField("Add a task, e.g. Draft outline 45m", text: $taskDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onSubmit {
                        if state.addTask(taskDraft, project: project.id, today: false) { taskDraft = "" }
                    }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 8))

            if open.isEmpty {
                Text("No tasks yet. Without any, Plan my day books a plain block of time for this project.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
                    .padding(.top, 2)
            }
            ForEach(open) { task in
                ProjectTaskRow(task: task)
                    .padding(.leading, -22)
            }
        }
    }
}

/// The project's dossier: the long-lived Markdown record that Lumberg keeps current.
struct DossierSection: View {
    @Environment(AppState.self) private var state
    let project: Project
    @State private var note = ""

    var body: some View {
        let dossier = state.dossier(project.id)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SectionLabel("DOSSIER")
                Spacer()
                if let slug = project.dossier, dossier != nil {
                    Button("Open") { NSWorkspace.shared.open(DossierStore.url(slug)) }
                        .buttonStyle(PillButton())
                        .tip("Open the dossier file to read or edit it")
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([DossierStore.url(slug)])
                    } label: {
                        Image(systemName: "folder").font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(IconButton(size: 28))
                    .tip("Show the file in Finder", align: .trailing)
                    .accessibilityLabel("Show the dossier in Finder")
                }
            }
            if let dossier {
                Text(dossier.summary ?? "Nothing written under \"What it is\" yet. Open the file to add it.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(dossier.summary == nil ? Theme.dim : Theme.paper)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.dim)
                    TextField("Add a dated note to the dossier's log", text: $note)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .onSubmit {
                            guard !note.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            state.addDossierNote(project.id, note)
                            note = ""
                        }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 8))
                if let last = Self.lastLog(dossier) {
                    Text(last)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(2)
                }
            } else {
                Text("No dossier file yet. It is written the next time the Projects screen opens.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
            }
        }
        .onAppear { state.scanIfStale(project.id) }
    }

    /// The newest line of the log, to confirm a note landed.
    private static func lastLog(_ d: Dossier) -> String? {
        let lines = d.body.components(separatedBy: "\n")
        guard let start = lines.lastIndex(where: { $0.trimmingCharacters(in: .whitespaces).lowercased() == "## log" }) else { return nil }
        let entries = lines[(start + 1)...].prefix { !$0.hasPrefix("## ") && !$0.hasPrefix("# ") }.filter { $0.hasPrefix("- ") }
        return entries.last.map { String($0.dropFirst(2)) }
    }
}

/// What the project's folder shows was done, a day at a time.
struct WorkCaptured: View {
    @Environment(AppState.self) private var state
    let project: Project
    @State private var copied: String?

    var body: some View {
        let captures = state.captures(for: project.id)
        let busy = state.scanning.contains(project.id)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SectionLabel("WORK CAPTURED")
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button(busy ? "Scanning…" : "Scan now") { state.scanWork(project.id) }
                    .buttonStyle(PillButton())
                    .disabled(busy || project.folder == nil)
                    .tip("Read the last \(WorkScanner.daysBack) days of commits, Claude Code sessions, session notes and changed files", align: .trailing)
            }
            .zIndex(1)

            if project.folder == nil {
                Text("Choose a project folder above and Lumberg will record what got done there: commits, what you asked Claude Code for, and files touched.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = state.scanErrors[project.id] {
                Text(error)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.amber)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if project.folder != nil, captures.isEmpty, !busy, state.scanErrors[project.id] == nil {
                Text("Not scanned yet. It also runs by itself whenever a focus block on this project ends.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.dim)
            }
            ForEach(captures) { c in
                day(c)
            }
        }
    }

    /// How long the folder shows work going on, and how much of that no focus block covers.
    @ViewBuilder private func offPlan(_ c: WorkCapture) -> some View {
        let active = WorkEvidence.minutes(c.active ?? [])
        let loose = WorkEvidence.minutes(state.unplanned(c))
        if active > 0 {
            HStack(spacing: 10) {
                Text(loose > 0
                     ? "About \(Quotes.format(active)) of work, \(Quotes.format(loose)) of it not in the plan"
                     : "About \(Quotes.format(active)) of work, all of it logged")
                    .font(Theme.mono(10.5))
                    .foregroundStyle(loose > 0 ? Theme.amber : Theme.green)
                if loose > 0 {
                    Button("Log it") { state.logUnplanned(c) }
                        .buttonStyle(PillButton())
                        .tip("Count this time toward the project's hours")
                }
            }
            .zIndex(1)
        }
    }

    private func label(_ c: WorkCapture) -> String {
        if c.day == state.todayKey { return "TODAY" }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: c.day) else { return c.day }
        return Fmt.shortDay.string(from: date).uppercased()
    }

    private func day(_ c: WorkCapture) -> some View {
        let writing = state.writingUp.contains(c.id)
        let timed = c.commits.map(\.inFocus) + c.prompts.map(\.inFocus) + c.sessionNotes.map(\.inFocus)
        let focused = timed.filter { $0 }.count
        let total = timed.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(label(c))
                    .font(Theme.mono(11, .bold))
                    .tracking(1.6)
                Text(headline(c))
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if !c.isEmpty {
                    if writing { ProgressView().controlSize(.small) }
                    Button(writing ? "Writing…" : (c.summary == nil ? "Write it up" : "Rewrite")) { state.writeUp(c) }
                        .buttonStyle(PillButton())
                        .disabled(writing)
                        .tip("Have Claude turn this into a short account of what got done", align: .trailing)
                    Button(copied == c.id ? "Copied" : "Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(
                            WorkEvidence.digest(c, project: project.name) { Fmt.timeAMPM.string(from: $0) },
                            forType: .string)
                        copied = c.id
                    }
                    .buttonStyle(PillButton())
                    .tip("Copy this day's record as text", align: .trailing)
                }
            }
            .zIndex(1)

            if c.isEmpty {
                Text("Nothing found in the folder for this day.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.dim)
            } else if total > 0 {
                Text("\(focused) of \(total) during focus blocks on this project")
                    .font(Theme.mono(10.5))
                    .foregroundStyle(focused > 0 ? Theme.green : Theme.dim)
            }

            offPlan(c)

            if let summary = c.summary {
                Text(summary)
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.bg.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
            }

            if !c.sessionNotes.isEmpty {
                group("SESSION NOTES") {
                    ForEach(c.sessionNotes) { item in
                        line(item.date, item.text, item.inFocus)
                    }
                }
            }
            if !c.commits.isEmpty {
                group("COMMITS") {
                    ForEach(c.commits) { item in
                        line(item.date, item.subject, item.inFocus)
                    }
                }
            }
            if !c.prompts.isEmpty {
                group("ASKED OF CLAUDE CODE") {
                    ForEach(c.prompts.suffix(12)) { item in
                        line(item.date, item.text, item.inFocus)
                    }
                    if c.prompts.count > 12 {
                        more("\(c.prompts.count - 12) earlier request\(c.prompts.count - 12 == 1 ? "" : "s") not shown")
                    }
                }
            }
            if !c.files.isEmpty {
                group("FILES TOUCHED") {
                    ForEach(c.files.prefix(10), id: \.self) { file in
                        Text(file)
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.paper.opacity(0.8))
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    if c.files.count > 10 { more("and \(c.files.count - 10) more") }
                }
            }
        }
        .padding(14)
        .background(Theme.raised.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
    }

    /// Focus time, then a count of each kind of evidence the day has.
    private func headline(_ c: WorkCapture) -> String {
        func count(_ n: Int, _ word: String) -> String? { n == 0 ? nil : "\(n) \(word)\(n == 1 ? "" : "s")" }
        return (["\(Quotes.format(c.focusMinutes)) focused"] + [
            count(c.sessionNotes.count, "session note"), count(c.commits.count, "commit"),
            count(c.prompts.count, "Claude request"), count(c.files.count, "file"),
        ].compactMap { $0 }).joined(separator: " · ")
    }

    private func group(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.mono(9.5, .bold))
                .tracking(1.6)
                .foregroundStyle(Theme.faint)
            content()
        }
    }

    private func more(_ text: String) -> some View {
        Text(text).font(Theme.mono(10.5)).foregroundStyle(Theme.dim)
    }

    private func line(_ date: Date, _ text: String, _ inFocus: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(inFocus ? Theme.green : Theme.faint)
                .frame(width: 6, height: 6)
                .accessibilityLabel(inFocus ? "During focus time" : "Outside focus time")
            Text(Fmt.time.string(from: date))
                .font(Theme.mono(11))
                .foregroundStyle(Theme.dim)
                .frame(width: 40, alignment: .trailing)
            Text(text)
                .font(.system(size: 12.5))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
