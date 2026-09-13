import Foundation
import UserNotifications

enum Notifier {
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

/// Detects upward crossings of usage thresholds and re-arms after a reset.
struct ThresholdTracker: Equatable {
    private var lastFired: [UsageWindow.Kind: Double] = [:]

    /// Returns thresholds that were newly crossed (upward) for the window.
    mutating func crossings(for window: UsageWindow, thresholds: [Double]) -> [Double] {
        let pct = window.percentUsed
        let fired = lastFired[window.kind]
        var newlyCrossed: [Double] = []

        if let previous = fired, pct < previous - 0.5 {
            // Usage dropped (window reset or usage removed) — re-arm everything.
            lastFired[window.kind] = nil
        }

        for threshold in thresholds.sorted() where pct >= threshold {
            if let previous = lastFired[window.kind], threshold <= previous { continue }
            newlyCrossed.append(threshold)
            lastFired[window.kind] = threshold
        }
        return newlyCrossed
    }

    mutating func reset() {
        lastFired = [:]
    }
}

@MainActor
final class UsageMonitor: ObservableObject {
    static let shared = UsageMonitor()

    enum State: Equatable {
        case idle
        case loading
        case loaded(UsageData)
        case needsAuth
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastRefresh: Date?

    private let fetcher = UsageFetcher()
    private var pollTask: Task<Void, Never>?
    private var tracker = ThresholdTracker()

    var usageData: UsageData? {
        if case .loaded(let data) = state { return data }
        return nil
    }

    init() {
        if let snapshot = SnapshotStore.load() {
            state = .loaded(snapshot)
            lastRefresh = snapshot.fetchedAt
        }
    }

    func start() {
        guard pollTask == nil else { return }
        poll()
    }

    func poll() {
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            await self?.runLoop()
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func runLoop() async {
        while !Task.isCancelled {
            await refreshOnce()
            let minutes = AppSettings.shared.refreshIntervalMinutes
            let seconds = Double(max(1, minutes)) * 60
            do {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            } catch {
                break
            }
        }
    }

    /// One fetch-parse-notify cycle; also used for the manual refresh button.
    func refreshOnce() async {
        guard let cookie = KeychainStore.loadCookie(), !cookie.isEmpty else {
            state = .needsAuth
            return
        }

        if usageData == nil { state = .loading }

        let html: String
        do {
            html = try await fetcher.fetchSettingsHTML(cookie: cookie)
        } catch let failure as FetchFailure {
            apply(failure: failure)
            return
        } catch is CancellationError {
            return
        } catch {
            state = .failed(error.localizedDescription)
            return
        }

        guard let usage = UsageParser.parse(html: html) else {
            state = .failed("Die Nutzungsdaten konnten nicht gelesen werden (Seite wurde möglicherweise geändert).")
            return
        }

        apply(usage: usage)
    }

    private func apply(usage: UsageData) {
        state = .loaded(usage)
        lastRefresh = usage.fetchedAt
        SnapshotStore.save(usage)
        fireNotificationsIfNeeded(for: usage)
    }

    private func apply(failure: FetchFailure) {
        switch failure {
        case .sessionExpired, .noCookie:
            KeychainStore.deleteCookie()
            state = .needsAuth
        case .http, .network:
            state = .failed(failure.errorDescription ?? "Unbekannter Fehler")
        }
    }

    private func fireNotificationsIfNeeded(for usage: UsageData) {
        let settings = AppSettings.shared
        guard settings.notificationsEnabled else { return }
        for window in usage.windows {
            let crossed = tracker.crossings(for: window, thresholds: settings.thresholds)
            guard let highest = crossed.max() else { continue }
            Notifier.post(
                title: "Ollama Cloud: \(window.kind.title)",
                body: String(format: "%.0f %% verbraucht (Schwelle %.0f %% erreicht)", window.percentUsed, highest)
            )
        }
    }

    // MARK: - Menu bar label

    var menuBarLabel: String {
        switch state {
        case .idle, .loading:
            return usageData.map { label(from: $0) } ?? "🦙"
        case .loaded(let data):
            return label(from: data)
        case .needsAuth:
            return "🦙 !"
        case .failed:
            return usageData.map { label(from: $0) } ?? "🦙"
        }
    }

    /// Text shown next to the template llama in the menu bar.
    var menuBarText: String {
        switch state {
        case .idle, .loading:
            return usageData.map { percentText(from: $0) } ?? ""
        case .loaded(let data):
            return percentText(from: data)
        case .needsAuth:
            return "!"
        case .failed:
            return usageData.map { percentText(from: $0) } ?? ""
        }
    }

    private func percentText(from data: UsageData) -> String {
        var parts: [String] = []
        if let fiveHour = data.window(.fiveHour) {
            parts.append(formatPercent(fiveHour.percentUsed))
        }
        if AppSettings.shared.showWeeklyInMenuBar, let weekly = data.window(.weekly) {
            parts.append(formatPercent(weekly.percentUsed))
        }
        return parts.joined(separator: " · ")
    }

    private func label(from data: UsageData) -> String {
        var parts: [String] = []
        if let fiveHour = data.window(.fiveHour) {
            parts.append(formatPercent(fiveHour.percentUsed))
        }
        if AppSettings.shared.showWeeklyInMenuBar, let weekly = data.window(.weekly) {
            parts.append(formatPercent(weekly.percentUsed))
        }
        return parts.isEmpty ? "🦙" : "🦙 \(parts.joined(separator: " · "))"
    }

    private func formatPercent(_ value: Double) -> String {
        value < 1 && value > 0
            ? String(format: "%.1f%%", value)
            : String(format: "%.0f%%", value)
    }
}