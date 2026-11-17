import LumbergCore
import SwiftUI

/// The right-hand column: today's list, or the projects it is drawn from.
struct TaskPanel: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                tab("TODAY", .today, "What you are doing today")
                tab("PROJECTS", .projects, "Standing work that Plan my day draws from")
                Spacer()
                Text("\(state.todayLog.pomodoros) FOCUS · \(state.todayLog.focusSeconds / 60)M")
                    .font(Theme.mono(10.5, .medium))
                    .foregroundStyle(Theme.dim)
                    .tip("Focus blocks finished and minutes focused today", align: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .zIndex(1)

            switch state.sideTab {
            case .today: TodayList()
            case .projects: ProjectsPanel()
            }
        }
    }

    private func tab(_ title: String, _ value: AppState.SideTab, _ hint: String) -> some View {
        let on = state.sideTab == value
        return Button {
            state.sideTab = value
        } label: {
            Text(title)
                .font(Theme.mono(10.5, .bold))
                .tracking(2)
                .foregroundStyle(on ? Theme.paper : Theme.dim)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(on ? Theme.raised : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tip(hint, align: .leading)
    }
}

struct TodayList: View {
    @Environment(AppState.self) private var state
    @State private var draft = ""
    @State private var editing: TaskItem?
    @FocusState private var addFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "plus").foregroundStyle(Theme.dim).font(.system(size: 12, weight: .bold))
                TextField("TPS cover sheets 50m !1 #work", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($addFocused)
                    .onSubmit {
                        if state.addTask(draft) { draft = "" }
                        addFocused = true
                    }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 12)

            Text("50m · 2h · !1 urgent · #work · @project")
                .lineLimit(1)
                .font(Theme.mono(9.5))
                .foregroundStyle(Theme.faint)
                .padding(.horizontal, 16)
                .padding(.top, 5)

            Button("") { addFocused = true }
                .keyboardShortcut("n", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)

            Button {
                if state.projects.isEmpty { state.openProjects(new: true) } else { state.planMyDay() }
            } label: {
                Label("Plan my day", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PillButton(filled: !state.projects.isEmpty))
            .keyboardShortcut("p", modifiers: .command)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .tip(state.projects.isEmpty
                 ? "Add a project first, then this fills your open time from it"
                 : "Fill today's open time with work from your projects (⌘P)")
            .zIndex(1)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(state.openTasks) { task in
                        TaskRow(task: task) { editing = task }
                    }
                    if state.openTasks.isEmpty {
                        Text("Nothing on the list. Add what you need to get done today, or press Plan my day to pull work in from your projects. New projects are made on the Projects screen, top right.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.dim)
                            .padding(14)
                    }
                    if !state.doneToday.isEmpty {
                        HStack {
                            SectionLabel("DONE TODAY")
                            Spacer()
                            if state.canClearDone {
                                Button("Clear") { state.clearCompleted() }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.dim)
                                    .tip("Remove finished tasks. Project tasks stay in their project.", align: .trailing)
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.top, 14)
                        ForEach(state.doneToday) { task in
                            TaskRow(task: task) { editing = task }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
            }
        }
        .popover(item: $editing, arrowEdge: .leading) { task in
            TaskEditor(task: task, projects: state.projects) { state.update($0) }
        }
    }
}

struct TaskRow: View {
    @Environment(AppState.self) private var state
    let task: TaskItem
    let edit: () -> Void
    @State private var hovering = false
    @State private var overCheck = false

    private var isActive: Bool { state.session?.taskID == task.id && state.session?.kind == .focus }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Button {
                state.setDone(task.id, !task.isDone)
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : (overCheck ? "checkmark.circle" : "circle"))
                    .font(.system(size: 16))
                    .foregroundStyle(task.isDone || overCheck ? Theme.green : Theme.dim)
            }
            .buttonStyle(.plain)
            .onHover { overCheck = $0 }
            .tip(task.isDone ? "Put back on the list" : "Mark done", align: .leading)
            .accessibilityLabel(task.isDone ? "Mark not done" : "Mark done")

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 13, weight: .medium))
                    .strikethrough(task.isDone)
                    .foregroundStyle(task.isDone ? Theme.dim : Theme.paper)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if task.priority == 1 {
                        Text("!1").font(Theme.mono(10, .bold)).foregroundStyle(Theme.red)
                    }
                    if let tag = task.tag {
                        Text(tag.short).font(Theme.mono(10, .bold)).foregroundStyle(Theme.color(for: tag))
                    }
                    if let project = state.project(task.projectID) {
                        Text(project.name).font(Theme.mono(10, .medium)).foregroundStyle(Theme.paper.opacity(0.75)).lineLimit(1)
                    }
                    Text(detail).font(Theme.mono(10)).foregroundStyle(Theme.dim)
                    if !task.isDone, state.isUnscheduled(task.id) {
                        Text("WON'T FIT").font(Theme.mono(9.5, .bold)).foregroundStyle(Theme.red)
                    }
                }
            }
            Spacer(minLength: 0)

            if hovering {
                Button(action: edit) {
                    Image(systemName: "pencil").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(IconButton())
                .tip("Edit name, time, priority", align: .trailing)
                .accessibilityLabel("Edit \(task.title)")

                Button {
                    state.delete(task.id)
                } label: {
                    Image(systemName: "trash").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(IconButton(tint: Theme.red))
                .tip("Delete", align: .trailing)
                .accessibilityLabel("Delete \(task.title)")
            }

            if !task.isDone, hovering || isActive {
                let running = isActive && state.session?.isPaused == false
                Button {
                    if isActive { state.togglePause() } else { state.startFocus(task) }
                } label: {
                    Image(systemName: running ? "pause.fill" : "play.fill").font(.system(size: 11))
                }
                .buttonStyle(IconButton(tint: Theme.green))
                .tip(running ? "Pause" : (isActive ? "Resume" : "Work on this now"), align: .trailing)
                .accessibilityLabel(running ? "Pause" : "Start \(task.title)")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(isActive ? Theme.green.opacity(0.1) : (hovering ? Theme.raised.opacity(0.6) : Color.clear),
                    in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .zIndex(hovering ? 1 : 0)
        .onTapGesture(count: 2, perform: edit)
        .contextMenu {
            if !task.isDone {
                Button("Start now") { state.startFocus(task) }
                Button("Move to top") { state.moveToTop(task.id) }
                if task.projectID != nil {
                    Button("Not today (back to project)") { state.setToday(task.id, false) }
                }
            }
            Button("Edit…", action: edit)
            Divider()
            Button("Delete", role: .destructive) { state.delete(task.id) }
        }
    }

    private var detail: String {
        let spent = task.spentSeconds / 60
        if task.isDone { return spent > 0 ? "\(Quotes.format(spent)) spent" : "done" }
        if spent == 0 { return Quotes.format(task.estimateMinutes) }
        return "\(Quotes.format(spent)) of \(Quotes.format(task.estimateMinutes))"
    }
}

struct TaskEditor: View {
    @State var task: TaskItem
    var projects: [Project] = []
    let save: (TaskItem) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Task", text: $task.title)
                .textFieldStyle(.roundedBorder)
            Stepper("Estimate: \(Quotes.format(task.estimateMinutes))", value: $task.estimateMinutes, in: 5...600, step: 5)
            Picker("Priority", selection: $task.priority) {
                Text("High").tag(1)
                Text("Normal").tag(2)
                Text("Low").tag(3)
            }
            .pickerStyle(.segmented)
            Picker("For", selection: $task.tag) {
                Text("None").tag(WorkTag?.none)
                ForEach(WorkTag.allCases) { Text($0.label).tag(WorkTag?.some($0)) }
            }
            if !projects.isEmpty {
                Picker("Project", selection: $task.projectID) {
                    Text("None").tag(UUID?.none)
                    ForEach(projects) { Text($0.name).tag(UUID?.some($0.id)) }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    save(task)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(task.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}
