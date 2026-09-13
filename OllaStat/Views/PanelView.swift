import SwiftUI

struct PanelView: View {
    @EnvironmentObject private var monitor: UsageMonitor
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.openSettings) private var openSettings

    private let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(spacing: 12) {
            header

            switch monitor.state {
            case .idle, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .needsAuth:
                NeedsAuthView()
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .loaded(let data):
                ForEach(data.windows) { window in
                    MeterCard(
                        window: window,
                        relativeFormatter: relativeFormatter
                    )
                }
            }

            Spacer(minLength: 0)
            footer
        }
        .padding(14)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Ollama Cloud Nutzung")
                .font(.headline)
            Spacer()
            if let last = monitor.lastRefresh {
                Text(last, format: .dateTime.hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                monitor.poll()
            } label: {
                Label("Aktualisieren", systemImage: "arrow.clockwise")
            }
            .disabled(monitor.state == .loading)

            Spacer()

            Button {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            } label: {
                Label("Einstellungen", systemImage: "gearshape")
            }

            Button {
                if let url = URL(string: "https://ollama.com/settings") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Image(systemName: "safari")
            }
            .help("ollama.com/settings im Browser öffnen")

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .help("OllaStat beenden")
        }
        .buttonStyle(.accessoryBar)
    }
}

private struct NeedsAuthView: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Kein oder abgelaufener Session-Cookie", systemImage: "lock")
                .font(.callout.weight(.semibold))
            Text("Hinterlege in den Einstellungen den Cookie „__Secure-session“ von ollama.com (DevTools → Application → Cookies).")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Einstellungen öffnen") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct MeterCard: View {
    let window: UsageWindow
    let relativeFormatter: RelativeDateTimeFormatter

    private var barColor: Color {
        switch window.percentUsed {
        case ..<50: return .green
        case ..<75: return .orange
        default: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.kind.title)
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(String(format: "%.1f %%", window.percentUsed))
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(barColor)
            }

            ProgressView(value: min(window.percentUsed, 100), total: 100)
                .tint(barColor)

            HStack {
                if let reset = window.resetsAt, reset > Date() {
                    Label(
                        "Resets \(relativeFormatter.localizedString(for: reset, relativeTo: Date()))",
                        systemImage: "clock.arrow.circlepath"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Label("Kein Verbrauch in diesem Zeitraum", systemImage: "minus.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if !window.models.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(window.models.prefix(4), id: \.model) { model in
                        HStack {
                            Text(model.model)
                                .font(.caption.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text("\(model.requests)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    if window.models.count > 4 {
                        Text("+ \(window.models.count - 4) weitere")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}