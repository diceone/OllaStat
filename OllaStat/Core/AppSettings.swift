import Foundation
import ServiceManagement
import Combine

/// User preferences backed by UserDefaults.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults: UserDefaults

    @Published var refreshIntervalMinutes: Int {
        didSet { defaults.set(refreshIntervalMinutes, forKey: "refreshIntervalMinutes") }
    }

    @Published var thresholds: [Double] {
        didSet { defaults.set(thresholds.map { String($0) }, forKey: "thresholds") }
    }

    @Published var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: "notificationsEnabled") }
    }

    @Published var showWeeklyInMenuBar: Bool {
        didSet { defaults.set(showWeeklyInMenuBar, forKey: "showWeeklyInMenuBar") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedInterval = defaults.object(forKey: "refreshIntervalMinutes") as? Int ?? 5
        self.refreshIntervalMinutes = storedInterval
        let storedThresholds: [Double]
        if let raw = defaults.stringArray(forKey: "thresholds") {
            let parsed = raw.compactMap { Double($0) }
            storedThresholds = parsed.isEmpty ? [50, 75, 90, 100] : parsed
        } else {
            storedThresholds = [50, 75, 90, 100]
        }
        self.thresholds = storedThresholds
        let storedNotifications = defaults.bool(forKey: "notificationsEnabled")
        self.notificationsEnabled = storedNotifications
        let storedWeekly = defaults.bool(forKey: "showWeeklyInMenuBar")
        self.showWeeklyInMenuBar = storedWeekly
    }

    var launchAtLoginEnabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("OllaStat: Launch-at-login-Fehler: \(error.localizedDescription)")
            }
            objectWillChange.send()
        }
    }
}

/// Persists the last fetched usage snapshot so the menu bar has data right after launch.
enum SnapshotStore {
    private static var fileURL: URL? {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("OllaStat", isDirectory: true)
        guard let base else { return nil }
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("usage.json")
    }

    static func load() -> UsageData? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(UsageData.self, from: data)
    }

    static func save(_ usage: UsageData) {
        guard let url = fileURL,
              let data = try? JSONEncoder().encode(usage) else { return }
        try? data.write(to: url, options: .atomic)
    }
}