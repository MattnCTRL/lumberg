import LumbergCore
import SwiftUI

/// The end-of-day summary.
struct ReportSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        let log = state.todayLog
        let sessions = log.sessions.filter { $0.kind == .focus }
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("TPS REPORT")
                        .font(Theme.mono(14, .heavy))
                        .tracking(3)
                    Text(Fmt.day.string(from: state.now))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                }
                Spacer()
                Button(copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(reportText, forType: .string)
                    copied = true
                }
                .buttonStyle(PillButton())
                Button("Close") { dismiss() }
                    .buttonStyle(PillButton(filled: true))
                    .keyboardShortcut(.cancelAction)
            }

            HStack(spacing: 10) {
                stat("\(log.pomodoros)", "FOCUS BLOCKS")
                stat(Quotes.format(log.focusSeconds / 60), "FOCUSED")
                stat("\(state.doneToday.count)", "TASKS DONE")
                stat("\(state.openTasks.count)", "STILL OPEN")
            }

            week

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !state.doneToday.isEmpty {
                        section("DONE") {
                            ForEach(state.doneToday) { t in
                                line(t.title, t.spentSeconds >= 60 ? Quotes.format(t.spentSeconds / 60) : "")
                            }
                        }
                    }
                    let worked = state.projects.filter { state.loggedThisWeek($0.id) > 0 }
                    if !worked.isEmpty {
                        section("PROJECTS THIS WEEK") {
                            ForEach(worked) { p in
                                line(p.name, "\(Quotes.format(state.loggedThisWeek(p.id))) of \(Quotes.format(p.weeklyTargetMinutes))")
                            }
                        }
                    }
                    ForEach(captured, id: \.capture.id) { item in
                        section("\(item.name.uppercased()): WORK CAPTURED") {
                            ForEach(captureLines(item.capture), id: \.self) { text in
                                Text(text)
                                    .font(.system(size: 13))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    if !offPlan.isEmpty {
                        section("NOT BUDGETED") {
                            ForEach(offPlan, id: \.name) { item in
                                line(item.name, "about \(Quotes.format(item.minutes))")
                            }
                        }
                    }
                    if !sessions.isEmpty {
                        section("WHERE THE TIME WENT") {
                            ForEach(sessions) { s in
                                line(s.title, Fmt.range(s.start, s.end))
                            }
                        }
                    }
                    if !state.openTasks.isEmpty {
                        section("CARRIED OVER") {
                            ForEach(state.openTasks) { t in
                                line(t.title, Quotes.format(t.remainingMinutes))
                            }
                        }
                    }
                    if state.doneToday.isEmpty, sessions.isEmpty, state.openTasks.isEmpty {
                        Text("Nothing to report yet.")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.dim)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .onAppear { state.findStrays() }
        .frame(width: 520, height: 560)
        .background(Theme.panel)
        .foregroundStyle(Theme.paper)
        .preferredColorScheme(.dark)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(Theme.mono(24, .bold))
            Text(label)
                .font(Theme.mono(9.5, .bold))
                .tracking(1.4)
                .foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 8))
    }

    /// Focus minutes for the last seven days, today on the right.
    private var week: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: state.now)
        let days = (0..<7).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
        let minutes = days.map { (state.log[Store.dayKey($0)]?.focusSeconds ?? 0) / 60 }
        let top = max(minutes.max() ?? 0, 60)
        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(days.enumerated()), id: \.offset) { i, day in
                VStack(spacing: 4) {
                    Text(minutes[i] > 0 ? Quotes.format(minutes[i]) : " ")
                        .font(Theme.mono(9))
                        .foregroundStyle(Theme.dim)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(i == days.count - 1 ? Theme.red : Theme.green.opacity(0.6))
                        .frame(height: max(2, CGFloat(minutes[i]) / CGFloat(top) * 54))
                    Text(Self.weekday.string(from: day).uppercased())
                        .font(Theme.mono(9, .bold))
                        .foregroundStyle(Theme.dim)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 90, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Focus time for the last seven days")
    }

    private static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            SectionLabel(title)
            content()
        }
    }

    private func line(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 13))
                .lineLimit(1)
            Spacer(minLength: 12)
            Text(detail)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.dim)
        }
    }

    /// Today's captured work for each project that has any.
    private var captured: [(name: String, capture: WorkCapture)] {
        state.captures.filter { $0.day == state.todayKey && !$0.isEmpty }.compactMap { c in
            state.project(c.projectID).map { ($0.name, c) }
        }
    }

    /// Today's work that no focus block covered: on projects, and in folders that are not one.
    private var offPlan: [(name: String, minutes: Int)] {
        let onProjects = state.captures.filter { $0.day == state.todayKey }.compactMap { c -> (name: String, minutes: Int)? in
            let minutes = WorkEvidence.minutes(state.unplanned(c))
            guard minutes > 0, let p = state.project(c.projectID) else { return nil }
            return (p.name, minutes)
        }
        return onProjects + state.strays.map { ("\($0.name) (no project)", $0.minutes) }
    }

    /// The write-up if there is one, otherwise the commit subjects.
    private func captureLines(_ c: WorkCapture) -> [String] {
        if let summary = c.summary, !summary.isEmpty { return [summary] }
        if !c.commits.isEmpty { return c.commits.map { "- \($0.subject)" } }
        return ["- \(c.prompts.count) Claude Code request\(c.prompts.count == 1 ? "" : "s"), \(c.files.count) file\(c.files.count == 1 ? "" : "s") touched"]
    }

    private var reportText: String {
        let log = state.todayLog
        var out = ["TPS report, \(Fmt.day.string(from: state.now))",
                   "\(log.pomodoros) focus blocks, \(Quotes.format(log.focusSeconds / 60)) focused", ""]
        if !state.doneToday.isEmpty {
            out.append("Done:")
            out += state.doneToday.map { "- \($0.title)" }
            out.append("")
        }
        for item in captured {
            out.append("\(item.name):")
            out += captureLines(item.capture)
            out.append("")
        }
        if !offPlan.isEmpty {
            out.append("Not budgeted:")
            out += offPlan.map { "- \($0.name): about \(Quotes.format($0.minutes))" }
            out.append("")
        }
        if !state.openTasks.isEmpty {
            out.append("Carried over:")
            out += state.openTasks.map { "- \($0.title) (\(Quotes.format($0.remainingMinutes)) left)" }
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
