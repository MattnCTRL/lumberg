import AppKit
import LumbergCore
import SwiftUI

/// The middle tier between the full window and the pop-ups: a small floating box that
/// shows the timer and what to work on while the main window is minimized or closed.
@MainActor
final class MiniPresenter {
    private var panel: NSPanel?
    private(set) var isShowing = false

    func show(state: AppState) {
        let panel = self.panel ?? {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 110),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isFloatingPanel = true
            p.level = .floating
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.hidesOnDeactivate = false
            p.isMovableByWindowBackground = true
            let host = NSHostingView(rootView: MiniView().environment(state))
            p.contentView = host
            p.setContentSize(host.fittingSize)
            // Bottom-right to start with; after that it stays wherever it is dragged.
            if !p.setFrameUsingName("LumbergMini"), let screen = NSScreen.main ?? NSScreen.screens.first {
                let f = screen.visibleFrame
                p.setFrameOrigin(NSPoint(x: f.maxX - p.frame.width - 18, y: f.minY + 18))
            }
            p.setFrameAutosaveName("LumbergMini")
            self.panel = p
            return p
        }()
        panel.orderFrontRegardless()
        isShowing = true
    }

    func hide() {
        guard isShowing else { return }
        isShowing = false
        panel?.orderOut(nil)
    }
}

struct MiniView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let s = state.session
        let tint: Color = s.map { $0.isPaused ? Theme.dim : Theme.color(for: $0.kind) } ?? Theme.dim
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(phase)
                        .font(Theme.mono(9.5, .bold))
                        .tracking(1.6)
                        .foregroundStyle(tint)
                    Text(s.map { Fmt.clock($0.remaining(at: state.now)) } ?? Fmt.time.string(from: state.now))
                        .font(Theme.mono(26, .bold))
                        .monospacedDigit()
                }
                .frame(width: 96, alignment: .leading)
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { state.showMain() } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(IconButton())
                .help("Open the full Lumberg window")
                .accessibilityLabel("Open Lumberg")
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.line)
                    Capsule().fill(tint).frame(width: geo.size.width * (s?.progress(at: state.now) ?? 0))
                }
            }
            .frame(height: 3)

            HStack(spacing: 6) {
                if let s {
                    small(s.isPaused ? "Resume" : "Pause", filled: s.isPaused) { state.togglePause() }
                    if s.kind == .focus {
                        if let id = s.taskID {
                            small("Done", filled: true, tint: Theme.green.opacity(0.75)) { state.setDone(id, true) }
                        }
                        small("Break") { state.needBreak() }
                        small("Stop") { state.stop() }
                    } else {
                        small("Skip break", filled: true) { state.startNext() }
                    }
                } else {
                    small("Start", filled: true) { state.startNext() }
                    small("Break") { state.needBreak() }
                }
                Spacer(minLength: 0)
                switchMenu
            }
        }
        .padding(12)
        .frame(width: 300)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(tint.opacity(0.5), lineWidth: 1))
        .foregroundStyle(Theme.paper)
        .padding(5)
        .preferredColorScheme(.dark)
    }

    /// Moves the timer to another project from the small box.
    @ViewBuilder private var switchMenu: some View {
        let active = state.projects.filter { $0.isBudgeted || $0.id == state.currentProject }
        let onBreak = state.session.map { $0.kind != .focus } ?? false
        if !active.isEmpty, !onBreak {
            Menu {
                ForEach(active) { p in
                    Button(p.id == state.currentProject ? "\(p.name) (now)" : p.name) { state.switchTo(p.id) }
                        .disabled(p.id == state.currentProject)
                }
            } label: {
                Text("Switch")
                    .font(.system(size: 11, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Move the timer to another project")
        }
    }

    private var phase: String {
        guard let s = state.session else {
            if state.currentMeeting != nil { return "IN A MEETING" }
            return state.inWorkHours ? "NOT WORKING" : "OFF THE CLOCK"
        }
        if s.isPaused { return "PAUSED" }
        return s.kind == .focus ? "FOCUS" : "BREAK"
    }

    private var title: String {
        if let s = state.session { return s.title }
        if let m = state.currentMeeting { return m.title }
        if let next = state.nextFocus { return "Next: \(next.title)" }
        return state.openTasks.isEmpty ? "Nothing on the list" : "No room left today"
    }

    private func small(_ title: String, filled: Bool = false, tint: Color = Theme.red, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(MiniButton(filled: filled, tint: tint))
    }
}

struct MiniButton: ButtonStyle {
    var filled = false
    var tint: Color = Theme.red

    func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration, filled: filled, tint: tint)
    }

    private struct Face: View {
        let configuration: Configuration
        let filled: Bool
        let tint: Color
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .foregroundStyle(filled ? Color.white : Theme.paper)
                .background(filled ? tint : Theme.raised, in: Capsule())
                .overlay(Capsule().fill(Color.white.opacity(hovering ? 0.12 : 0)))
                .opacity(configuration.isPressed ? 0.7 : 1)
                .contentShape(Capsule())
                .onHover { hovering = $0 }
        }
    }
}

/// Hands the hosting NSWindow to whoever needs it.
struct WindowReader: NSViewRepresentable {
    let found: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            if let window = view?.window { found(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            if let window = nsView?.window { found(window) }
        }
    }
}
