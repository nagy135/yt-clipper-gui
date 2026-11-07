import Foundation

public struct ClipError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct ClipRequest: Sendable {
    public let url: URL
    public let start: Double
    public let end: Double?

    public init(link: String, start: String = "", end: String = "") throws {
        let link = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: link), let host = url.host?.lowercased(),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com"),
              url.user == nil, url.password == nil else {
            throw ClipError("Enter a valid YouTube link.")
        }
        self.url = url
        self.start = try Self.seconds(start) ?? 0
        self.end = try Self.seconds(end)
        if let end = self.end, end <= self.start {
            throw ClipError("End time must be after start time.")
        }
    }

    public static func seconds(_ text: String) throws -> Double? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { throw invalidTime() }
        var total = 0.0
        for (index, part) in parts.enumerated() {
            let last = index == parts.count - 1
            let pattern = last ? #"^[0-9]+(?:\.[0-9]+)?$"# : #"^[0-9]+$"#
            guard part.range(of: pattern, options: .regularExpression) != nil,
                  let value = Double(part), value.isFinite,
                  (index == 0 || value < 60) else { throw invalidTime() }
            total = total * 60 + value
        }
        guard total.isFinite, total < 1_000_000_000 else { throw invalidTime() }
        return total
    }

    private static func invalidTime() -> ClipError {
        ClipError("Use seconds, MM:SS, or HH:MM:SS (for example 18, 0:18, or 1:02:03).")
    }
}
