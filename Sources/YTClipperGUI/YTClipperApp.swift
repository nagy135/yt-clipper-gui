import SwiftUI
import AppKit
import ClipperCore

@main
struct YTClipperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        Window("YouTube Clipper", id: "main") {
            ContentView(model: delegate.model)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = ClipModel()
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.busy else { return .terminateNow }
        Task {
            await model.cancelAndWait()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}


@MainActor
final class ClipModel: ObservableObject {
    @Published var link = ""
    @Published var start = ""
    @Published var end = ""
    @Published var busy = false
    @Published var status = ""
    @Published var error: String?
    @Published var output: URL?
    @Published var outputFileSize: String?
    @Published var copied = false
    private var runner: CommandRunner?
    private var job: Task<Void, Never>?

    var outputDirectory: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("YouTube Clips", isDirectory: true)
    }

    func create() {
        guard !busy else { return }
        do {
            let request = try ClipRequest(link: link, start: start, end: end)
            let tools = try Toolchain.discover()
            let runner = CommandRunner()
            self.runner = runner
            busy = true; error = nil; output = nil; outputFileSize = nil; copied = false
            status = "Preparing…"
            job = Task {
                defer { busy = false; self.runner = nil }
                do {
                    output = try await ClipEngine().create(request, tools: tools, runner: runner,
                        outputDirectory: outputDirectory) { [weak self] phase in
                            await self?.updatePhase(phase)
                        }
                    if let output {
                        let attributes = try? FileManager.default.attributesOfItem(atPath: output.path)
                        if let size = attributes?[.size] as? NSNumber {
                            outputFileSize = ByteCountFormatter.string(fromByteCount: size.int64Value, countStyle: .file)
                        }
                    }
                    status = "Your clip is ready."
                } catch is CancellationError {
                    status = "Cancelled."
                } catch {
                    self.error = error.localizedDescription
                    status = "Couldn’t create the clip."
                }
            }
        } catch { self.error = error.localizedDescription }
    }

    private func updatePhase(_ phase: String) { status = phase }

    func cancelAndWait() async {
        await runner?.cancel()
        await job?.value
    }

    func cancel() {
        guard let runner else { return }
        status = "Cancelling…"
        Task { await runner.cancel() }
    }

    func copy() {
        guard let output else { return }
        guard FileManager.default.fileExists(atPath: output.path) else {
            error = "This clip has been moved or deleted. Create another clip to copy it."; return
        }
        NSPasteboard.general.clearContents()
        copied = NSPasteboard.general.writeObjects([output as NSURL])
        if !copied { error = "The clip could not be copied. Please try again." }
    }

    func reveal() {
        guard let output else { return }
        NSWorkspace.shared.activateFileViewerSelecting([output])
    }
}

struct ContentView: View {
    @ObservedObject var model: ClipModel
    @FocusState private var linkFocused: Bool
    private let accent = Color(red: 0.88, green: 0.24, blue: 0.20)

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 5) {
                    Text("YouTube Clipper").font(.system(size: 24, weight: .semibold, design: .rounded))
                    Text("A link. A moment. A clip to keep.").foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("YouTube link").font(.headline)
                    TextField("https://www.youtube.com/watch?v=…", text: $model.link)
                        .textFieldStyle(.roundedBorder).focused($linkFocused)
                        .onSubmit { model.create() }
                        .accessibilityIdentifier("youtubeLink")
                }
                HStack(spacing: 16) {
                    timeField("From", placeholder: "Start", text: $model.start, id: "startTime")
                    Image(systemName: "arrow.right").foregroundStyle(.tertiary).padding(.top, 23)
                    timeField("To", placeholder: "Full length", text: $model.end, id: "endTime")
                }
                Text("Times are optional. Use seconds, MM:SS, or HH:MM:SS.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .disabled(model.busy)

            HStack {
                Label("Downloads / YouTube Clips", systemImage: "folder")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if model.busy {
                    Button("Cancel") { model.cancel() }
                }
                Button { model.create() } label: {
                    Label("Create clip", systemImage: "scissors")
                        .padding(.horizontal, 9).padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent).tint(accent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.busy || model.link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("createClip")
            }

            if model.busy {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text(model.status).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(14).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            } else if let output = model.output {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Your clip is ready", systemImage: "checkmark.circle.fill")
                        .font(.headline).foregroundStyle(.green)
                    Text(output.lastPathComponent).font(.caption).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if let fileSize = model.outputFileSize {
                        Text("File size: \(fileSize)").font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button { model.copy() } label: {
                            Label(model.copied ? "Copied!" : "Copy to clipboard", systemImage: model.copied ? "checkmark" : "doc.on.doc")
                        }
                        .accessibilityIdentifier("copyClip")
                        Button { model.reveal() } label: { Label("Show in Finder", systemImage: "folder") }
                            .accessibilityIdentifier("showInFinder")
                    }
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            } else if !model.status.isEmpty && model.error == nil {
                Text(model.status).font(.caption).foregroundStyle(.secondary)
            }

            if let error = model.error {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Couldn’t create the clip", systemImage: "exclamationmark.triangle")
                        .font(.headline).foregroundStyle(.red)
                    ScrollView { Text(error).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                        .frame(maxHeight: 120)
                }
                .padding(14).background(.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(28).frame(width: 540)
        .onAppear { linkFocused = true }
    }

    private func timeField(_ title: String, placeholder: String, text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
                .monospacedDigit().accessibilityIdentifier(id)
                .onSubmit { model.create() }
        }
    }
}
