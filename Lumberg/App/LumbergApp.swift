import LumbergCore
import SwiftUI

struct LumbergApp: App {
    @State private var state = AppState()

    var body: some Scene {
        Window("Lumberg", id: "main") {
            MainView()
                .environment(state)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        // Closing the window leaves this running, so the pop-ups keep coming.
        MenuBarExtra {
            MenuContent()
                .environment(state)
        } label: {
            MenuBarLabel(state: state)
        }

        Settings {
            SettingsView()
                .environment(state)
        }
    }
}

struct MenuBarLabel: View {
    let state: AppState

    var body: some View {
        if let s = state.session {
            HStack(spacing: 4) {
                Image(systemName: s.isPaused ? "pause.fill" : (s.kind == .focus ? "mug.fill" : "cup.and.saucer.fill"))
                Text(Fmt.clock(s.remaining(at: state.now))).monospacedDigit()
            }
        } else {
            Image(systemName: "mug")
                .accessibilityLabel("Lumberg")
        }
    }
}

struct MenuContent: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let s = state.session {
            Text("\(s.isPaused ? "Paused" : (s.kind == .focus ? "Focus" : "Break")): \(s.title)")
            Button(s.isPaused ? "Resume" : "Pause") { state.togglePause() }
            if s.kind == .focus {
                if let id = s.taskID {
                    Button("Mark done") { state.setDone(id, true) }
                }
                Button("I need a break") { state.needBreak() }
                Button("Stop") { state.stop() }
            } else {
                Button("Skip break") { state.startNext() }
            }
        } else {
            if let next = state.nextFocus {
                Text("Next: \(next.title) at \(Fmt.time.string(from: next.start))")
            } else {
                Text(state.openTasks.isEmpty ? "Nothing on the list" : "No room left today")
            }
            Button("Start next focus block") { state.startNext() }
            Button("Plan my day…") {
                open()
                state.planMyDay()
            }
            .disabled(state.projects.isEmpty)
            Button("I need a break") { state.needBreak() }
        }

        if let m = state.nextMeeting {
            Divider()
            Text("\(m.title) at \(Fmt.timeAMPM.string(from: m.start))")
        }

        Divider()
        Button("Open Lumberg") { open() }
        Button("Projects…") {
            open()
            state.openProjects()
        }
        Button("Read calendar photo…") {
            open()
            state.showImport = true
        }
        Button("TPS report") {
            open()
            state.showReport = true
        }
        SettingsLink { Text("Settings…") }
        Divider()
        Button("Quit Lumberg") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func open() {
        openWindow(id: "main")
        state.showMain()
    }
}
