import LumbergCore
import SwiftUI

/// Where projects live: each one a weekly target, a progress bar and a backlog of tasks.
struct ProjectsPanel: View {
    @Environment(AppState.self) private var state
    @State private var expanded: Set<UUID> = []

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
        VStack(alignment: .leading, spacing: 0) {
            Button {
                state.openProjects(new: true)
            } label: {
                Label("New project", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PillButton())
            .tip("Open the Projects screen to set one up")
            .padding(.horizontal, 12)
            .zIndex(1)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(sorted) { project in
                        ProjectRow(project: project,
                                   isOpen: expanded.contains(project.id),
                                   toggle: {
                                       if expanded.contains(project.id) { expanded.remove(project.id) } else { expanded.insert(project.id) }
                                   },
                                   edit: { state.openProjects(select: project.id) })
                    }
                    if state.projects.isEmpty {
                        Text("No projects yet. Press New project to set one up for each piece of ongoing work. Plan my day then splits your open time between them.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.dim)
                            .padding(14)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
            }
        }
    }
}

struct ProjectRow: View {
    @Environment(AppState.self) private var state
    let project: Project
    let isOpen: Bool
    let toggle: () -> Void
    let edit: () -> Void
    @State private var hovering = false
    @State private var confirmDelete = false
    @State private var draft = ""

    var body: some View {
        let all = state.tasks(in: project.id)
        let open = Planner.queue(all)
        let logged = state.loggedThisWeek(project.id)
        let target = max(project.weeklyTargetMinutes, 1)
        let color = Theme.color(for: project.client)

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.dim)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .frame(width: 12, height: 16)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(project.name)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        if project.priority == 1 {
                            Text("!1").font(Theme.mono(10, .bold)).foregroundStyle(Theme.red)
                        }
                        if project.status != .active {
                            Text(project.status.label.uppercased()).font(Theme.mono(9, .bold)).foregroundStyle(Theme.amber)
                        }
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.line)
                            Capsule().fill(color)
                                .frame(width: geo.size.width * min(1, CGFloat(logged) / CGFloat(target)))
                        }
                    }
                    .frame(height: 4)
                    HStack(spacing: 6) {
                        if let client = project.client {
                            Text(client.short).font(Theme.mono(10, .bold)).foregroundStyle(color)
                        }
                        Text("\(Quotes.format(logged)) of \(Quotes.format(project.weeklyTargetMinutes)) this week · \(open.count) open")
                            .font(Theme.mono(10))
                            .foregroundStyle(Theme.dim)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)

                if hovering {
                    Button(action: edit) {
                        Image(systemName: "pencil").font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(IconButton())
                    .tip("Open on the Projects screen: details, folder, captured work", align: .trailing)
                    .accessibilityLabel("Edit \(project.name)")

                    Button {
                        var p = project
                        p.status = project.status == .active ? .paused : .active
                        state.updateProject(p)
                    } label: {
                        Image(systemName: project.status == .active ? "pause.fill" : "play.fill").font(.system(size: 10))
                    }
                    .buttonStyle(IconButton(tint: Theme.amber))
                    .tip(project.status == .active ? "Pause: leave it out of Plan my day" : "Make active again", align: .trailing)
                    .accessibilityLabel(project.status == .active ? "Pause \(project.name)" : "Resume \(project.name)")

                    Button { confirmDelete = true } label: {
                        Image(systemName: "trash").font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(IconButton(tint: Theme.red))
                    .tip("Delete project", align: .trailing)
                    .accessibilityLabel("Delete \(project.name)")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture(perform: toggle)

            if isOpen {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(open) { task in
                        ProjectTaskRow(task: task)
                    }
                    let done = all.filter(\.isDone).count
                    if done > 0 {
                        Text("\(done) finished")
                            .font(Theme.mono(10))
                            .foregroundStyle(Theme.faint)
                            .padding(.leading, 30)
                            .padding(.vertical, 2)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.dim)
                        TextField("Add a task, e.g. Draft outline 45m", text: $draft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .onSubmit {
                                if state.addTask(draft, project: project.id, today: false) { draft = "" }
                            }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Theme.bg.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                    .padding(.leading, 22)
                    .padding(.trailing, 8)
                    .padding(.top, 2)
                    .padding(.bottom, 8)
                }
            }
        }
        .background(hovering || isOpen ? Theme.raised.opacity(0.6) : Theme.raised.opacity(0.25),
                    in: RoundedRectangle(cornerRadius: 8))
        .opacity(project.status == .active ? 1 : 0.6)
        .onHover { hovering = $0 }
        .zIndex(hovering ? 1 : 0)
        .confirmationDialog("Delete \(project.name)?", isPresented: $confirmDelete) {
            Button("Delete project and its tasks", role: .destructive) { state.deleteProject(project.id) }
        } message: {
            Text("Its tasks are removed. Time already logged stays in your reports.")
        }
    }
}

/// A task inside a project's backlog.
struct ProjectTaskRow: View {
    @Environment(AppState.self) private var state
    let task: TaskItem
    @State private var hovering = false

    var body: some View {
        let today = state.isOnToday(task)
        HStack(spacing: 8) {
            Button { state.setDone(task.id, true) } label: {
                Image(systemName: "circle").font(.system(size: 13))
            }
            .buttonStyle(IconButton(size: 18, tint: Theme.green))
            .tip("Mark done", align: .leading)
            .accessibilityLabel("Mark \(task.title) done")

            Text(task.title)
                .font(.system(size: 12.5))
                .lineLimit(1)
            if task.priority == 1 {
                Text("!1").font(Theme.mono(9.5, .bold)).foregroundStyle(Theme.red)
            }
            Spacer(minLength: 4)
            Text(Quotes.format(task.remainingMinutes))
                .font(Theme.mono(10))
                .foregroundStyle(Theme.dim)

            if today || hovering {
                Button { state.setToday(task.id, !today) } label: {
                    Image(systemName: today ? "sun.max.fill" : "sun.max").font(.system(size: 11))
                }
                .buttonStyle(IconButton(size: 20, tint: Theme.amber))
                .tip(today ? "On today's list. Click to take it off." : "Do this today", align: .trailing)
                .accessibilityLabel(today ? "Take off today" : "Add to today")
            }
            if hovering {
                Button { state.delete(task.id) } label: {
                    Image(systemName: "trash").font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(IconButton(size: 20, tint: Theme.red))
                .tip("Delete task", align: .trailing)
                .accessibilityLabel("Delete \(task.title)")
            }
        }
        .padding(.leading, 22)
        .padding(.trailing, 8)
        .frame(minHeight: 24)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .zIndex(hovering ? 1 : 0)
    }
}
