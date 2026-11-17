import LumbergCore
import SwiftUI
import UniformTypeIdentifiers

/// Photo of a calendar in, events out. Nothing is added until you confirm.
struct ImportSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case idle, reading
        case result(PhotoParser.Result)
        case failed(String)
    }

    @State private var image: NSImage?
    @State private var phase: Phase = .idle
    @State private var picked: Set<UUID> = []
    @State private var targeted = false
    @State private var job: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("CALENDAR PHOTO")
                    .font(Theme.mono(14, .heavy))
                    .tracking(3)
                Spacer()
                Button("Close") { close() }
                    .buttonStyle(PillButton())
                    .keyboardShortcut(.cancelAction)
            }

            HStack(alignment: .top, spacing: 16) {
                dropZone
                    .frame(width: 300, height: 340)
                results
                    .frame(width: 380, height: 340, alignment: .topLeading)
            }

            HStack(spacing: 10) {
                Button("Choose photo…") { choose() }
                    .buttonStyle(PillButton())
                Button("Paste") { paste() }
                    .buttonStyle(PillButton())
                    .keyboardShortcut("v", modifiers: .command)
                if !state.photoEvents.isEmpty {
                    Button("Forget photo events") { state.clearPhotoEvents() }
                        .buttonStyle(PillButton())
                        .help("Removes every event read from earlier photos")
                }
                Spacer()
                if case .result(let r) = phase, !r.events.isEmpty {
                    Button("Add \(picked.count) to my calendar") {
                        state.importPhotoEvents(r.events.filter { picked.contains($0.id) })
                        close()
                    }
                    .buttonStyle(PillButton(filled: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(picked.isEmpty)
                }
            }
        }
        .padding(20)
        .background(Theme.panel)
        .foregroundStyle(Theme.paper)
        .preferredColorScheme(.dark)
    }

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.bg)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(6)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 34))
                        .foregroundStyle(Theme.dim)
                    Text("Drop a photo or screenshot of the calendar here, paste one with ⌘V, or choose a file.")
                        .font(.system(size: 12.5))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.dim)
                        .padding(.horizontal, 24)
                }
            }
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(targeted ? Theme.red : Theme.line,
                              style: StrokeStyle(lineWidth: targeted ? 2 : 1, dash: image == nil ? [6, 5] : []))
        }
        .onDrop(of: [.fileURL, .image], isTargeted: $targeted) { providers in
            guard let provider = providers.first else { return false }
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, let img = NSImage(contentsOf: url) else { return }
                    Task { @MainActor in read(img) }
                }
            } else {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data, let img = NSImage(data: data) else { return }
                    Task { @MainActor in read(img) }
                }
            }
            return true
        }
    }

    @ViewBuilder
    private var results: some View {
        switch phase {
        case .idle:
            VStack(alignment: .leading, spacing: 8) {
                Text("Yeahhh, if you could go ahead and show me your calendar, that'd be great.")
                    .font(.system(size: 14, weight: .medium))
                    .italic()
                Text("Outlook day, week or month view all work. The picture is sent to Claude to be read; the events it finds are listed here for you to check before anything is added.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.dim)
            }
        case .reading:
            VStack(alignment: .leading, spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Reading the calendar. This usually takes 10 to 30 seconds.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.dim)
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                Text("That didn't work.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.red)
                Text(message)
                    .font(.system(size: 12.5))
                    .textSelection(.enabled)
                if let image {
                    Button("Try again") { read(image) }
                        .buttonStyle(PillButton())
                }
            }
        case .result(let r):
            VStack(alignment: .leading, spacing: 8) {
                if r.events.isEmpty {
                    Text("No events found in that picture.")
                        .font(.system(size: 14, weight: .semibold))
                }
                if !r.notes.isEmpty {
                    Text(r.notes)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(r.events) { e in
                            eventRow(e)
                        }
                    }
                }
                Text("Times in the photo are read as \(PhotoParser.zone.identifier). They are shown here in yours. Events on a day replace what was read for that day before.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
            }
        }
    }

    private func eventRow(_ e: ImportedEvent) -> some View {
        let on = picked.contains(e.id)
        return Button {
            if on { picked.remove(e.id) } else { picked.insert(e.id) }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .foregroundStyle(on ? Theme.red : Theme.dim)
                VStack(alignment: .leading, spacing: 1) {
                    Text(e.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(when(e))
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.dim)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(on ? 1 : 0.55)
    }

    private func when(_ e: ImportedEvent) -> String {
        let day = Fmt.shortDay.string(from: e.start)
        var text = e.isAllDay ? "\(day) · all day" : "\(day) · \(Fmt.range(e.start, e.end))"
        if let location = e.location { text += " · \(location)" }
        return text
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a photo or screenshot of the calendar"
        guard panel.runModal() == .OK, let url = panel.url, let img = NSImage(contentsOf: url) else { return }
        read(img)
    }

    private func paste() {
        let board = NSPasteboard.general
        if let img = NSImage(pasteboard: board) {
            read(img)
        } else if let url = (board.readObjects(forClasses: [NSURL.self]) as? [URL])?.first,
                  let img = NSImage(contentsOf: url) {
            read(img)
        } else {
            phase = .failed("There is no picture on the clipboard.")
        }
    }

    private func read(_ img: NSImage) {
        job?.cancel()
        image = img
        phase = .reading
        let model = state.settings.model
        job = Task {
            do {
                let result = try await PhotoInterpreter.interpret(image: img, model: model)
                if Task.isCancelled { return }
                picked = Set(result.events.map(\.id))
                phase = .result(result)
            } catch {
                if Task.isCancelled { return }
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func close() {
        job?.cancel()
        dismiss()
    }
}
