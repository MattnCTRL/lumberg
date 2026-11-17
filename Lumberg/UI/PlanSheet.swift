import LumbergCore
import SwiftUI

/// Plan my day's suggestion. Nothing is added to today until it is accepted.
struct PlanSheet: View {
    @Environment(AppState.self) private var state
    let proposal: Proposal
    @State private var picked: Set<UUID> = []

    private var chosen: [Proposal.Line] { proposal.lines.filter { picked.contains($0.id) } }

    var body: some View {
        let groups = Dictionary(grouping: proposal.lines, by: \.projectID)
        let order = proposal.lines.map(\.projectID).reduce(into: [UUID]()) { if !$0.contains($1) { $0.append($1) } }
        let total = chosen.reduce(0) { $0 + $1.minutes }

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("PLAN MY DAY")
                    .font(Theme.mono(14, .heavy))
                    .tracking(3)
                Spacer()
                Button("Cancel") { state.proposal = nil }
                    .buttonStyle(PillButton())
                    .keyboardShortcut(.cancelAction)
            }

            if proposal.lines.isEmpty {
                Text(emptyReason)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            } else {
                Text("Yeahhh, I went ahead and split your open time between your projects. Untick anything you'd rather not do today.")
                    .font(.system(size: 13, weight: .medium))
                    .italic()
                    .fixedSize(horizontal: false, vertical: true)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(order, id: \.self) { id in
                            if let project = state.project(id) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Circle().fill(Theme.color(for: project.client)).frame(width: 8, height: 8)
                                        Text(project.name).font(.system(size: 13, weight: .semibold))
                                        Spacer()
                                        Text("\(Quotes.format(state.loggedThisWeek(id))) of \(Quotes.format(project.weeklyTargetMinutes)) this week · today \(Quotes.format(proposal.shares[id] ?? 0))")
                                            .font(Theme.mono(10))
                                            .foregroundStyle(Theme.dim)
                                    }
                                    ForEach(groups[id] ?? []) { line in
                                        row(line)
                                    }
                                }
                            }
                        }
                    }
                }

                HStack {
                    Text("Open focus time \(Quotes.format(state.openFocusMinutes)) · adding \(Quotes.format(total))")
                        .font(Theme.mono(11, .medium))
                        .foregroundStyle(total > state.openFocusMinutes ? Theme.red : Theme.dim)
                    Spacer()
                    Button("Add to today") { state.accept(chosen) }
                        .buttonStyle(PillButton(filled: true))
                        .keyboardShortcut(.defaultAction)
                        .disabled(chosen.isEmpty)
                }
            }
        }
        .padding(20)
        .frame(width: 540, height: 480)
        .background(Theme.panel)
        .foregroundStyle(Theme.paper)
        .preferredColorScheme(.dark)
        .onAppear { picked = Set(proposal.lines.map(\.id)) }
    }

    private var emptyReason: String {
        if !state.projects.contains(where: { $0.status == .active }) {
            return "There are no active projects to plan from."
        }
        if proposal.budgetMinutes < 15 {
            return "There is no open time left today to plan into. Either the work day is over, or today's list already fills it."
        }
        return "Every active project is already at its weekly target, or already has its share on today's list."
    }

    private func row(_ line: Proposal.Line) -> some View {
        let on = picked.contains(line.id)
        return Button {
            if on { picked.remove(line.id) } else { picked.insert(line.id) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .foregroundStyle(on ? Theme.red : Theme.dim)
                Text(line.title)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                if line.taskID == nil {
                    Text("TIME BLOCK").font(Theme.mono(9, .bold)).foregroundStyle(Theme.amber)
                }
                Spacer(minLength: 0)
                Text(Quotes.format(line.minutes))
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.dim)
            }
            .padding(.vertical, 4)
            .padding(.leading, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(on ? 1 : 0.5)
    }
}
