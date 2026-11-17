import LumbergCore
import SwiftUI

/// The day as a vertical rail: meetings, finished sessions, the running timer and the plan ahead.
struct DayTimeline: View {
    @Environment(AppState.self) private var state

    private let ppm: CGFloat = 1.5
    private let gutter: CGFloat = 46

    private struct Item: Identifiable {
        enum Style { case meeting(Color), focus, rest, done, active(Color) }
        var id: String
        var start: Date
        var end: Date
        var title: String
        var detail: String
        var style: Style
        var column = 0
        var columns = 1
    }

    var body: some View {
        let range = hourRange
        let items = layout(buildItems())
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionLabel("TODAY")
                Spacer()
                if !state.hasCalendarAccess {
                    Button("Connect calendars") { state.requestCalendarAccess() }
                        .buttonStyle(PillButton(filled: true))
                        .tip("Let Lumberg read your Mac's calendars so it can plan around meetings", align: .trailing)
                } else {
                    let on = state.calendarList.filter { state.isCalendarOn($0) }
                    let meetings = state.agenda.filter { !$0.isAllDay }.count
                    SettingsLink {
                        Text("\(on.count) CALENDAR\(on.count == 1 ? "" : "S") · \(meetings) TODAY")
                            .font(Theme.mono(10, .medium))
                            .foregroundStyle(Theme.dim)
                    }
                    .buttonStyle(.plain)
                    .tip(on.isEmpty
                         ? "Connected, but no calendars are switched on. Click to choose."
                         : "Reading: \(Set(on.map { $0.account.isEmpty ? $0.title : $0.account }).sorted().joined(separator: ", ")). Click to choose calendars.",
                         align: .trailing)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .zIndex(1)

            ScrollViewReader { proxy in
                ScrollView {
                    GeometryReader { geo in
                        let width = geo.size.width - gutter - 12
                        ZStack(alignment: .topLeading) {
                            ForEach(range.lowerBound...range.upperBound, id: \.self) { hour in
                                HStack(alignment: .top, spacing: 6) {
                                    Text(hourLabel(hour))
                                        .font(Theme.mono(10))
                                        .foregroundStyle(Theme.faint)
                                        .frame(width: gutter - 10, alignment: .trailing)
                                        .offset(y: -6)
                                    Rectangle().fill(Theme.line).frame(height: 1)
                                }
                                .offset(y: y(hour: hour, range))
                                .id(hour)
                            }

                            ForEach(items) { item in
                                block(item, width: width)
                                    .offset(x: gutter + CGFloat(item.column) * width / CGFloat(item.columns),
                                            y: y(item.start, range))
                            }

                            if let nowY = nowOffset(range) {
                                HStack(spacing: 0) {
                                    Circle().fill(Theme.red).frame(width: 7, height: 7)
                                    Rectangle().fill(Theme.red).frame(height: 1.5)
                                }
                                .offset(x: gutter - 4, y: nowY - 3.5)
                            }
                        }
                    }
                    .frame(height: CGFloat((range.upperBound - range.lowerBound) * 60) * ppm + 24)
                    .padding(.top, 14)
                }
                .onAppear {
                    let hour = Calendar.current.component(.hour, from: Date())
                    proxy.scrollTo(max(range.lowerBound, min(hour - 1, range.upperBound)), anchor: .top)
                }
            }
        }
    }

    // MARK: Geometry

    private var dayStart: Date { Calendar.current.startOfDay(for: state.minuteNow) }

    private var hourRange: ClosedRange<Int> {
        var lo = state.settings.planner.workStart / 60
        var hi = (state.settings.planner.workEnd + 59) / 60
        for e in state.agenda where !e.isAllDay {
            lo = min(lo, Int(e.start.timeIntervalSince(dayStart) / 3600))
            hi = max(hi, Int((e.end.timeIntervalSince(dayStart) / 3600).rounded(.up)))
        }
        for s in state.todayLog.sessions {
            lo = min(lo, Int(s.start.timeIntervalSince(dayStart) / 3600))
            hi = max(hi, Int((s.end.timeIntervalSince(dayStart) / 3600).rounded(.up)))
        }
        let nowHour = Calendar.current.component(.hour, from: state.minuteNow)
        lo = min(lo, nowHour)
        hi = max(hi, nowHour + 1)
        return max(0, lo)...min(24, max(hi, lo + 1))
    }

    private func y(hour: Int, _ range: ClosedRange<Int>) -> CGFloat {
        CGFloat((hour - range.lowerBound) * 60) * ppm
    }

    private func y(_ date: Date, _ range: ClosedRange<Int>) -> CGFloat {
        CGFloat(date.timeIntervalSince(dayStart) / 60 - Double(range.lowerBound * 60)) * ppm
    }

    private func nowOffset(_ range: ClosedRange<Int>) -> CGFloat? {
        let value = y(state.minuteNow, range)
        return value >= 0 ? value : nil
    }

    private func hourLabel(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        return "\(h)\(hour % 24 < 12 ? "a" : "p")"
    }

    // MARK: Items

    private func buildItems() -> [Item] {
        var items: [Item] = []
        let now = state.minuteNow

        for s in state.todayLog.sessions where s.kind == .focus {
            items.append(Item(id: "log-\(s.id)", start: s.start, end: s.end, title: s.title,
                              detail: "done", style: .done))
        }
        if let s = state.session, !s.isPaused {
            items.append(Item(id: "active", start: s.segmentStart, end: s.endsAt, title: s.title,
                              detail: "now", style: .active(Theme.color(for: s.kind))))
        }
        for b in state.plan.blocks {
            switch b.kind {
            case .meeting:
                let color = Color(hexString: b.event?.colorHex)
                items.append(Item(id: b.id, start: b.start, end: b.end, title: b.title,
                                  detail: b.event?.source ?? "", style: .meeting(color)))
            case .focus where b.end > now:
                items.append(Item(id: b.id, start: b.start, end: b.end, title: b.title,
                                  detail: "\(b.minutes)m", style: .focus))
            case .shortBreak where b.end > now, .longBreak where b.end > now:
                items.append(Item(id: b.id, start: b.start, end: b.end, title: b.title, detail: "", style: .rest))
            default:
                break
            }
        }
        return items.sorted { $0.start < $1.start }
    }

    /// Side-by-side columns for anything that overlaps.
    private func layout(_ items: [Item]) -> [Item] {
        var out = items
        var cluster: [Int] = []
        var clusterEnd = Date.distantPast
        var columnEnds: [Date] = []

        func close() {
            for i in cluster { out[i].columns = max(columnEnds.count, 1) }
            cluster = []
            columnEnds = []
        }

        for i in out.indices {
            if out[i].start >= clusterEnd { close() }
            if let free = columnEnds.firstIndex(where: { $0 <= out[i].start }) {
                out[i].column = free
                columnEnds[free] = out[i].end
            } else {
                out[i].column = columnEnds.count
                columnEnds.append(out[i].end)
            }
            cluster.append(i)
            clusterEnd = max(clusterEnd, out[i].end)
        }
        close()
        return out
    }

    @ViewBuilder
    private func block(_ item: Item, width: CGFloat) -> some View {
        let height = max(CGFloat(item.end.timeIntervalSince(item.start) / 60) * ppm - 2, 6)
        let w = width / CGFloat(item.columns) - 3
        let (fill, edge, text): (Color, Color, Color) = {
            switch item.style {
            case .meeting(let c): return (c.opacity(0.22), c, Theme.paper)
            case .focus: return (Theme.green.opacity(0.13), Theme.green, Theme.paper)
            case .rest: return (Theme.amber.opacity(0.1), Theme.amber.opacity(0.7), Theme.dim)
            case .done: return (Theme.paper.opacity(0.05), Theme.faint, Theme.dim)
            case .active(let c): return (c.opacity(0.32), c, Theme.paper)
            }
        }()

        HStack(spacing: 0) {
            Rectangle().fill(edge).frame(width: 3)
            if height >= 15 {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        if case .done = item.style {
                            Image(systemName: "checkmark").font(.system(size: 8, weight: .bold))
                        }
                        Text(item.title)
                            .font(.system(size: 11.5, weight: .semibold))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if height < 30, !item.detail.isEmpty {
                            Text(item.detail).font(Theme.mono(9.5)).foregroundStyle(Theme.dim)
                        }
                    }
                    if height >= 30 {
                        Text("\(Fmt.range(item.start, item.end))\(item.detail.isEmpty ? "" : " · \(item.detail)")")
                            .font(Theme.mono(9.5))
                            .foregroundStyle(Theme.dim)
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(text)
                .padding(.horizontal, 6)
                .padding(.top, 2)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            Spacer(minLength: 0)
        }
        .frame(width: max(w, 10), height: height)
        .background(fill)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .help("\(item.title) · \(Fmt.range(item.start, item.end))")
    }
}
