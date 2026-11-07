import Foundation

public struct Toolchain: Sendable {
    public let ytDLP: URL
    public let ffmpeg: URL
    public let ffprobe: URL
    public let path: String

    public init(ytDLP: URL, ffmpeg: URL, ffprobe: URL, path: String) {
        self.ytDLP = ytDLP; self.ffmpeg = ffmpeg; self.ffprobe = ffprobe; self.path = path
    }

    public static func discover() throws -> Toolchain {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = ["/opt/homebrew/bin", "/usr/local/bin", "/run/current-system/sw/bin",
                     "\(home)/.nix-profile/bin", "\(home)/.local/bin", "/usr/bin", "/bin"]
            + (ProcessInfo.processInfo.environment["PATH"] ?? "").components(separatedBy: ":")
        func find(_ name: String) throws -> URL {
            for path in paths where !path.isEmpty {
                let url = URL(fileURLWithPath: path).appendingPathComponent(name)
                if FileManager.default.isExecutableFile(atPath: url.path) { return url }
            }
            throw ClipError("Missing \(name). Install yt-dlp and FFmpeg, then try again. Homebrew: brew install yt-dlp ffmpeg")
        }
        return try Toolchain(ytDLP: find("yt-dlp"), ffmpeg: find("ffmpeg"), ffprobe: find("ffprobe"), path: paths.joined(separator: ":"))
    }
}

/// One runner per job. File-backed output avoids pipe deadlocks during long downloads.
public actor CommandRunner {
    private var process: Process?
    private var cancelled = false
    public init() {}
    public func cancel() {
        cancelled = true
        if let process, process.isRunning { process.interrupt() }
    }

    public func run(_ executable: URL, _ arguments: [String], path: String) async throws -> String {
        if cancelled { throw CancellationError() }
        let log = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        _ = FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close(); try? FileManager.default.removeItem(at: log) }
        let child = Process()
        child.executableURL = executable
        child.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = path
        child.environment = environment
        child.standardOutput = handle
        child.standardError = handle
        child.standardInput = FileHandle.nullDevice
        process = child
        defer { process = nil }
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            child.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try child.run() } catch { continuation.resume(throwing: error) }
        }
        if cancelled { throw CancellationError() }
        let output = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        guard status == 0 else {
            throw ClipError("\(executable.lastPathComponent) failed (\(status)).\n\n\(output.suffix(6000))")
        }
        return output
    }
}

public struct ClipEngine: Sendable {
    public init() {}
    public func create(_ request: ClipRequest, tools: Toolchain, runner: CommandRunner,
                       outputDirectory: URL,
                       phase: @Sendable (String) async -> Void) async throws -> URL {
        let fm = FileManager.default
        let workspace = fm.temporaryDirectory.appendingPathComponent("yt-clipper-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workspace) }
        let manifest = workspace.appendingPathComponent("download.txt")
        await phase("Downloading video…")
        _ = try await runner.run(tools.ytDLP, [
            "--ignore-config", "--no-playlist", "--no-progress", "--no-simulate",
            "--ffmpeg-location", tools.ffmpeg.deletingLastPathComponent().path,
            "--merge-output-format", "mkv", "-f",
            "bestvideo[height<=1080]+bestaudio/best[height<=1080]/best",
            "-o", workspace.appendingPathComponent("source.%(ext)s").path,
            "--print-to-file", "after_move:filepath", manifest.path, "--", request.url.absoluteString
        ], path: tools.path)
        let sourcePath = try String(contentsOf: manifest, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        guard fm.fileExists(atPath: sourcePath) else { throw ClipError("The downloaded video could not be found.") }
        await phase("Checking clip times…")
        let rawDuration = try await runner.run(tools.ffprobe, ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", sourcePath], path: tools.path)
        guard let duration = Double(rawDuration.trimmingCharacters(in: .whitespacesAndNewlines)), duration.isFinite, duration > 0 else {
            throw ClipError("Could not read the video duration.")
        }
        guard request.start < duration else { throw ClipError("Start time is past the end of the video.") }
        if let end = request.end, end > duration + 0.1 { throw ClipError("End time is past the end of the video (\(Int(duration)) seconds).") }
        try fm.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let output = outputDirectory.appendingPathComponent("Clip \(stamp) \(UUID().uuidString.prefix(6)).mp4")
        var finished = false
        defer { if !finished { try? fm.removeItem(at: output) } }
        await phase("Creating MP4 clip…")
        var args = ["-nostdin", "-hide_banner", "-loglevel", "error", "-i", sourcePath,
                    "-ss", String(request.start)]
        if let end = request.end { args += ["-t", String(min(end, duration) - request.start)] }
        args += ["-map", "0:v:0", "-map", "0:a:0?", "-c:v", "libx264", "-preset", "medium", "-crf", "18",
                 "-pix_fmt", "yuv420p", "-c:a", "aac", "-movflags", "+faststart", "-n", output.path]
        _ = try await runner.run(tools.ffmpeg, args, path: tools.path)
        guard let size = try fm.attributesOfItem(atPath: output.path)[.size] as? NSNumber, size.intValue > 0 else {
            throw ClipError("FFmpeg did not create a video file.")
        }
        finished = true
        return output
    }
}
