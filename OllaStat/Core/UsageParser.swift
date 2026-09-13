import Foundation

/// One usage window as shown on ollama.com/settings.
struct UsageWindow: Codable, Equatable, Identifiable {
    enum Kind: String, Codable, CaseIterable {
        case fiveHour
        case weekly

        var title: String {
            switch self {
            case .fiveHour: return "5-Stunden-Fenster"
            case .weekly: return "Wochennutzung"
            }
        }

        var shortLabel: String {
            switch self {
            case .fiveHour: return "5h"
            case .weekly: return "7d"
            }
        }
    }

    var kind: Kind
    var percentUsed: Double
    var resetsAt: Date?
    var models: [ModelUsage]

    var id: Kind { kind }
}

struct ModelUsage: Codable, Equatable {
    var model: String
    var requests: Int
}

/// Complete snapshot of the settings page usage meters.
struct UsageData: Codable, Equatable {
    var windows: [UsageWindow]
    var fetchedAt: Date

    func window(_ kind: UsageWindow.Kind) -> UsageWindow? {
        windows.first { $0.kind == kind }
    }
}

enum UsageParser {
    /// Parses the usage meters from the ollama.com/settings HTML.
    /// Returns nil when the page contains no usage markers at all.
    static func parse(html: String) -> UsageData? {
        guard let root = HTMLParser.parse(html) else { return nil }
        let tracks = root.descendants { $0.attribute("data-usage-track") != nil }
        guard !tracks.isEmpty else { return nil }

        var windows: [UsageWindow] = []
        for track in tracks {
            guard let ariaLabel = track.attribute("aria-label") else { continue }
            guard let kind = identifier(from: ariaLabel) else { continue }
            guard let percent = percentage(from: ariaLabel) else { continue }

            let segments = track.descendants { $0.attribute("data-usage-segment") != nil }
                .compactMap { segment -> ModelUsage? in
                    guard let model = segment.attribute("data-model"), !model.isEmpty else { return nil }
                    let requests = Int(segment.attribute("data-requests") ?? "0") ?? 0
                    return ModelUsage(model: model, requests: requests)
                }

            windows.append(
                UsageWindow(
                    kind: kind,
                    percentUsed: percent,
                    resetsAt: resetDate(from: track),
                    models: segments
                )
            )
        }
        guard !windows.isEmpty else { return nil }
        return UsageData(windows: windows, fetchedAt: Date())
    }

    private static func identifier(from ariaLabel: String) -> UsageWindow.Kind? {
        let lowered = ariaLabel.lowercased()
        if lowered.contains("session") { return .fiveHour }
        if lowered.contains("weekly") { return .weekly }
        return nil
    }

    private static func percentage(from ariaLabel: String) -> Double? {
        guard let match = ariaLabel.range(of: #"[0-9]+(?:\.[0-9]+)?"#, options: .regularExpression) else { return nil }
        return Double(ariaLabel[match])
    }

    private static func resetDate(from track: HTMLElement) -> Date? {
        guard let meter = track.nearestAncestor(where: { $0.attribute("data-usage-meter") != nil }) else { return nil }
        guard let resetElement = meter.nextSibling(where: { $0.attribute("data-time") != nil }) else { return nil }
        guard let raw = resetElement.attribute("data-time") else { return nil }
        return parseISO8601(raw)
    }

    static func parseISO8601(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}