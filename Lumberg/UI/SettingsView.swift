import LumbergCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("Day", systemImage: "timer") }
            CalendarSettings()
                .tabItem { Label("Calendars", systemImage: "calendar") }
            ClaudeSettings()
                .tabItem { Label("Calendar photos", systemImage: "camera.viewfinder") }
        }
        .frame(width: 480, height: 440)
        .onChange(of: state.settings) { state.commit() }
    }
}

private struct GeneralSettings: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        Form {
            Section("Work hours") {
                DatePicker("Start", selection: time(\.workStart), displayedComponents: .hourAndMinute)
                DatePicker("End", selection: time(\.workEnd), displayedComponents: .hourAndMinute)
            }
            Section("Timer") {
                Stepper("Focus: \(state.settings.planner.focusMinutes) min",
                        value: $state.settings.planner.focusMinutes, in: 10...90, step: 5)
                Stepper("Short break: \(state.settings.planner.shortBreakMinutes) min",
                        value: $state.settings.planner.shortBreakMinutes, in: 1...30)
                Stepper("Long break: \(state.settings.planner.longBreakMinutes) min",
                        value: $state.settings.planner.longBreakMinutes, in: 5...60, step: 5)
                Stepper("Long break after \(state.settings.planner.cyclesBeforeLongBreak) focus blocks",
                        value: $state.settings.planner.cyclesBeforeLongBreak, in: 2...8)
                Toggle("Start breaks automatically", isOn: $state.settings.autoStartBreaks)
            }
            Section("Pop-ups") {
                Stepper("Nag every \(state.settings.nagIntervalMinutes) min when I'm not working",
                        value: $state.settings.nagIntervalMinutes, in: 1...60)
                Stepper("Warn \(state.settings.meetingLeadMinutes) min before a meeting",
                        value: $state.settings.meetingLeadMinutes, in: 1...30)
                Stepper("Stop focus \(state.settings.planner.meetingBufferMinutes) min before a meeting",
                        value: $state.settings.planner.meetingBufferMinutes, in: 0...15)
                Toggle("Sounds", isOn: $state.settings.soundsOn)
            }
        }
        .formStyle(.grouped)
    }

    /// Minutes-after-midnight as a time of day. The end is kept at least an hour after the start.
    private func time(_ key: WritableKeyPath<PlannerSettings, Int>) -> Binding<Date> {
        Binding {
            Calendar.current.startOfDay(for: Date())
                .addingTimeInterval(Double(state.settings.planner[keyPath: key]) * 60)
        } set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            var p = state.settings.planner
            p[keyPath: key] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            p.workStart = min(p.workStart, 22 * 60)
            if p.workEnd < p.workStart + 60 { p.workEnd = p.workStart + 60 }
            state.settings.planner = p
        }
    }
}

private struct CalendarSettings: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Form {
            if !state.hasCalendarAccess {
                Section {
                    Text("Lumberg has not been allowed to read your calendars yet.")
                    Button("Connect calendars") { state.requestCalendarAccess() }
                    Text("If no prompt appears, turn it on in System Settings > Privacy & Security > Calendars.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if state.calendarList.isEmpty {
                Section {
                    Text("macOS has no calendars. Add your Google or Microsoft accounts in System Settings > Internet Accounts with Calendars switched on, and they will appear here.")
                }
            } else {
                let groups = Dictionary(grouping: state.calendarList, by: \.account)
                ForEach(groups.keys.sorted(), id: \.self) { account in
                    Section(account.isEmpty ? "Other" : account) {
                        ForEach(groups[account] ?? []) { info in
                            Toggle(isOn: Binding(
                                get: { state.isCalendarOn(info) },
                                set: { state.setCalendar(info, on: $0) })) {
                                HStack(spacing: 8) {
                                    Circle().fill(Color(hexString: info.colorHex)).frame(width: 9, height: 9)
                                    Text(info.title)
                                }
                            }
                        }
                    }
                }
                Section {
                    Text("A calendar that is missing here has to be added to macOS first: System Settings > Internet Accounts.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ClaudeSettings: View {
    @Environment(AppState.self) private var state
    @State private var key = ""
    @State private var hasKey = PhotoInterpreter.storedAPIKey != nil

    var body: some View {
        @Bindable var state = state
        Form {
            Section("Reading calendar photos") {
                Text(hasKey ? "Using the API key saved on this Mac (billed per use)." : PhotoInterpreter.route)
                    .foregroundStyle(.secondary)
                Text("An API key is optional. Leave it empty to use your Claude subscription.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                SecureField("Anthropic API key (optional)", text: $key)
                HStack {
                    Button("Save key") {
                        PhotoInterpreter.saveAPIKey(key)
                        key = ""
                        hasKey = PhotoInterpreter.storedAPIKey != nil
                    }
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                    if hasKey {
                        Button("Remove key") {
                            PhotoInterpreter.saveAPIKey("")
                            hasKey = false
                        }
                    }
                }
                TextField("Model", text: $state.settings.model)
            }
            Section("Stored photo events") {
                Text("\(state.photoEvents.count) event\(state.photoEvents.count == 1 ? "" : "s") read from photos. They are dropped after two weeks.")
                    .foregroundStyle(.secondary)
                Button("Forget them now") { state.clearPhotoEvents() }
                    .disabled(state.photoEvents.isEmpty)
            }
        }
        .formStyle(.grouped)
    }

}
