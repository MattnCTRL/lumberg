import LumbergCore
import SwiftUI

struct MainView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var state = state
        ZStack {
            Theme.bg.ignoresSafeArea()

            AsciiBackdrop(mood: state.mood)
                .foregroundStyle(Theme.paper.opacity(0.2))
                .padding(.top, 70)
                .padding(.horizontal, 300)

            VStack(spacing: 0) {
                header
                    .zIndex(2)
                Divider().overlay(Theme.line)
                if state.showProjects {
                    ProjectsScreen()
                } else {
                    HStack(spacing: 0) {
                        DayTimeline()
                            .frame(width: 330)
                            .background(Theme.panel.opacity(0.92))
                        Divider().overlay(Theme.line)
                        TimerPanel()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Divider().overlay(Theme.line)
                        TaskPanel()
                            .frame(width: 340)
                            .background(Theme.panel.opacity(0.92))
                    }
                }
            }
        }
        .foregroundStyle(Theme.paper)
        .preferredColorScheme(.dark)
        .frame(minWidth: 1080, minHeight: 680)
        .sheet(isPresented: $state.showImport) { ImportSheet().environment(self.state) }
        .sheet(isPresented: $state.showReport) { ReportSheet().environment(self.state) }
        .sheet(isPresented: Binding(get: { self.state.proposal != nil },
                                    set: { if !$0 { self.state.proposal = nil } })) {
            if let proposal = self.state.proposal {
                PlanSheet(proposal: proposal).environment(self.state)
            }
        }
        .background(WindowReader { self.state.attach($0) })
        .onAppear {
            state.openMain = {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Text("LUMBERG")
                .font(Theme.mono(19, .heavy))
                .tracking(5)
            Text(Fmt.day.string(from: state.minuteNow).uppercased())
                .font(Theme.mono(11, .medium))
                .tracking(1.6)
                .foregroundStyle(Theme.dim)

            ForEach(state.agenda.filter(\.isAllDay)) { e in
                Chip(text: e.title, color: Color(hexString: e.colorHex))
            }

            Spacer()

            if state.plan.demandMinutes > 0 {
                Chip(text: "WORK \(Quotes.format(state.plan.demandMinutes))", color: Theme.paper)
                    .tip("Time your open tasks still need")
                Chip(text: "FREE \(Quotes.format(state.plan.freeMinutes))", color: Theme.green)
                    .tip("Time left today inside work hours, outside meetings")
                if state.plan.overMinutes > 0 {
                    Chip(text: "OVER \(Quotes.format(state.plan.overMinutes))", color: Theme.red, filled: true)
                        .tip("Work that will not fit today")
                }
            }

            Button {
                if state.showProjects { state.showProjects = false } else { state.openProjects() }
            } label: {
                Label(state.showProjects ? "Back to my day" : "Projects",
                      systemImage: state.showProjects ? "chevron.left" : "folder")
            }
            .buttonStyle(PillButton(filled: state.showProjects))
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .tip(state.showProjects ? "Return to the timer and today's list (⇧⌘P)"
                                    : "Add and manage projects, and see the work captured for each (⇧⌘P)")

            Button {
                state.showImport = true
            } label: {
                Label("Calendar photo", systemImage: "camera.viewfinder")
            }
            .buttonStyle(PillButton())
            .keyboardShortcut("i", modifiers: .command)
            .tip("Add meetings from a photo or screenshot of a calendar (⌘I)")

            Button {
                state.showReport = true
            } label: {
                Label("TPS report", systemImage: "doc.text")
            }
            .buttonStyle(PillButton())
            .keyboardShortcut("r", modifiers: .command)
            .tip("Today's summary: focus time, what got done, what carries over (⌘R)")

            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(PillButton())
            .tip("Settings: work hours, timer lengths, calendars (⌘,)", align: .trailing)
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 18)
        .padding(.top, 34)
        .padding(.bottom, 12)
        .background(Theme.panel.opacity(0.92))
    }
}

struct Chip: View {
    var text: String
    var color: Color
    var filled = false

    var body: some View {
        Text(text)
            .font(Theme.mono(10.5, .bold))
            .tracking(1)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(filled ? Color.white : color)
            .background(filled ? color : color.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
    }
}

// MARK: - Timer

struct TimerPanel: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            ring
            controls
            switcher
            Text(state.quote)
                .font(.system(size: 15, weight: .medium))
                .italic()
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.paper.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Theme.bg.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
            upNext
            Spacer(minLength: 0)
        }
        .padding(24)
    }

    private var tint: Color {
        guard let s = state.session else { return Theme.faint }
        return s.isPaused ? Theme.dim : Theme.color(for: s.kind)
    }

    private var ring: some View {
        let s = state.session
        return ZStack {
            Circle().fill(Theme.bg.opacity(0.42))
            Circle().stroke(Theme.line, lineWidth: 10)
            Circle()
                .trim(from: 0, to: s?.progress(at: state.now) ?? 0)
                .stroke(tint, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: state.now)
            VStack(spacing: 6) {
                Text(phaseLabel)
                    .font(Theme.mono(11, .bold))
                    .tracking(2.4)
                    .foregroundStyle(tint == Theme.faint ? Theme.dim : tint)
                Text(s.map { Fmt.clock($0.remaining(at: state.now)) } ?? Fmt.time.string(from: state.now))
                    .font(Theme.mono(62, .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .shadow(color: Theme.bg, radius: 6)
                Text(subtitle)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 210)
            }
        }
        .frame(width: 290, height: 290)
    }

    private var phaseLabel: String {
        guard let s = state.session else {
            if state.currentMeeting != nil { return "IN A MEETING" }
            return state.inWorkHours ? "NOT WORKING" : "OFF THE CLOCK"
        }
        if s.isPaused { return "PAUSED" }
        switch s.kind {
        case .focus: return "FOCUS \(state.todayLog.pomodoros + 1)"
        case .longBreak: return "LONG BREAK"
        default: return "BREAK"
        }
    }

    private var subtitle: String {
        if let s = state.session { return s.title }
        if let m = state.currentMeeting { return m.title }
        if let next = state.nextFocus {
            return "Next: \(next.title) at \(Fmt.time.string(from: next.start))"
        }
        return state.openTasks.isEmpty ? "Nothing on the list" : "No room left today"
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 10) {
            if let s = state.session {
                Button(s.isPaused ? "Resume" : "Pause") { state.togglePause() }
                    .buttonStyle(PillButton(filled: s.isPaused))
                    .keyboardShortcut(.return, modifiers: .command)
                    .tip(s.isPaused ? "Carry on where you left off (⌘↩)" : "Hold the timer (⌘↩)", above: true)
                Button("+5 min") { state.extend(minutes: 5) }
                    .buttonStyle(PillButton())
                    .tip("Add five minutes to this block", above: true)
                if s.kind == .focus {
                    if let id = s.taskID {
                        Button("Done") { state.setDone(id, true) }
                            .buttonStyle(PillButton(filled: true, tint: Theme.green.opacity(0.75)))
                            .keyboardShortcut("d", modifiers: .command)
                            .tip("This task is finished (⌘D)", above: true)
                    }
                    Button("I need a break") { state.needBreak() }
                        .buttonStyle(PillButton(filled: true, tint: Theme.amber.opacity(0.8)))
                        .keyboardShortcut("b", modifiers: .command)
                        .tip("Take a short break now, then come back to this (⌘B)", above: true)
                    Button("Stop") { state.stop() }
                        .buttonStyle(PillButton())
                        .tip("Stop the timer. Time worked so far is kept.", above: true)
                } else {
                    Button("Skip break") { state.startNext() }
                        .buttonStyle(PillButton(filled: true))
                        .tip("End the break and start the next task", above: true)
                }
            } else {
                Button {
                    state.startNext()
                } label: {
                    Label(startLabel, systemImage: "play.fill")
                        .lineLimit(1)
                }
                .buttonStyle(PillButton(filled: true))
                .keyboardShortcut(.return, modifiers: .command)
                .tip("Start a focus block on this task (⌘↩)", above: true)
                Button("I need a break") { state.needBreak() }
                    .buttonStyle(PillButton())
                    .keyboardShortcut("b", modifiers: .command)
                    .tip("Start a short break timer (⌘B)", above: true)
            }
        }
    }

    /// One click moves the timer to another project. The clock keeps running.
    @ViewBuilder
    private var switcher: some View {
        let current = state.currentProject
        let active = state.projects.filter { $0.isBudgeted || $0.id == current }
        let onBreak = state.session.map { $0.kind != .focus } ?? false
        if !active.isEmpty, !onBreak {
            VStack(spacing: 7) {
                SectionLabel(state.session == nil ? "START ON" : "SWITCH TO")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 200), spacing: 6)], spacing: 6) {
                    ForEach(active) { p in
                        Button {
                            state.switchTo(p.id)
                        } label: {
                            Text(p.name).lineLimit(1).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PillButton(filled: p.id == current, tint: Theme.color(for: p.client)))
                        .disabled(p.id == current)
                        .tip(p.id == current ? "The timer is on this project"
                             : "Move the timer to \(p.name). Time so far stays where it was spent.", above: true)
                    }
                }
                .frame(maxWidth: 420)
            }
            .zIndex(1)
        }
    }

    private var startLabel: String {
        if let next = state.nextFocus { return "Start \(next.title)" }
        if let first = state.openTasks.first { return "Start \(first.title)" }
        return "Start open focus"
    }

    private var upNext: some View {
        let upcoming = state.plan.blocks.filter { $0.end > state.minuteNow }.prefix(4)
        return VStack(alignment: .leading, spacing: 6) {
            if !upcoming.isEmpty {
                SectionLabel("UP NEXT")
                ForEach(Array(upcoming)) { block in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(block.kind == .meeting ? Color(hexString: block.event?.colorHex) : Theme.color(for: block.kind))
                            .frame(width: 4, height: 16)
                        Text(Fmt.time.string(from: block.start))
                            .font(Theme.mono(12, .medium))
                            .foregroundStyle(Theme.dim)
                            .frame(width: 44, alignment: .trailing)
                        Text(block.title)
                            .font(.system(size: 13))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text("\(block.minutes)m")
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.dim)
                    }
                }
            }
        }
        .frame(maxWidth: 360, alignment: .leading)
        .padding(upcoming.isEmpty ? 0 : 12)
        .background(Theme.bg.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
    }
}
