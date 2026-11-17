import AppKit
import LumbergCore
import SwiftUI

struct NagAction: Identifiable {
    let id = UUID()
    var title: String
    var primary: Bool
    var run: () -> Void
}

struct Nag: Identifiable {
    let id = UUID()
    var mood: Mood
    var title: String
    var message: String
    var actions: [NagAction]
}

/// The pop-up: a floating panel in the top-right corner that shows over every
/// Space and over full-screen apps, and does not steal keyboard focus.
@MainActor
final class NagPresenter {
    private var panel: NSPanel?
    private(set) var isShowing = false

    func show(_ nag: Nag) {
        let view = NagView(nag: nag) { [weak self] in self?.dismiss() }
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize

        let panel = self.panel ?? {
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            p.isFloatingPanel = true
            p.level = .statusBar
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.hidesOnDeactivate = false
            p.isMovableByWindowBackground = true
            self.panel = p
            return p
        }()

        panel.contentView = host
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let frame = screen.visibleFrame
            panel.setFrame(NSRect(x: frame.maxX - size.width - 18, y: frame.maxY - size.height - 14,
                                  width: size.width, height: size.height), display: true)
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            panel.animator().alphaValue = 1
        }
        isShowing = true
    }

    func dismiss() {
        guard isShowing, let panel else { return }
        isShowing = false
        panel.orderOut(nil)
    }
}

struct NagView: View {
    let nag: Nag
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(AsciiPortrait.render(cols: 30, rows: 16, view: AsciiPortrait.faceView, mood: nag.mood).joined(separator: "\n"))
                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.paper.opacity(0.9))
                .fixedSize()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(nag.title)
                        .font(Theme.mono(11, .bold))
                        .tracking(2)
                        .foregroundStyle(Theme.red)
                    Spacer()
                    Button(action: dismiss) {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(IconButton(size: 20))
                    .help("Dismiss")
                    .accessibilityLabel("Dismiss")
                }
                Text(nag.message)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.paper)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Spacer()
                    ForEach(nag.actions) { action in
                        Button(action.title) {
                            dismiss()
                            action.run()
                        }
                        .buttonStyle(PillButton(filled: action.primary))
                    }
                }
            }
            .frame(width: 290)
        }
        .padding(16)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.red.opacity(0.55), lineWidth: 1))
        .padding(6)
        .preferredColorScheme(.dark)
    }
}
