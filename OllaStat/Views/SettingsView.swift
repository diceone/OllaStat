import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    @State private var launchAtLogin = false
    @State private var showLogin = false

    private static let intervals = [1, 2, 5, 10, 15, 30, 60]

    var body: some View {
        Form {
            Section("Anmeldung bei ollama.com") {
                Button {
                    showLogin = true
                } label: {
                    Label(KeychainStore.hasCookie() ? "Erneut anmelden …" : "Bei ollama.com anmelden …",
                          systemImage: "person.badge.key")
                }
                .buttonStyle(.borderedProminent)

                Text("Öffnet ein eingebettetes Browserfenster — OllaStat fängt das Session-Cookie selbst ab, prüft es und speichert es im Schlüsselbund.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if KeychainStore.hasCookie() {
                    HStack {
                        Image(systemName: "key.fill")
                            .foregroundStyle(.secondary)
                        Text("Cookie ist im Schlüsselbund gespeichert.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Entfernen", role: .destructive) {
                            KeychainStore.deleteCookie()
                        }
                        .font(.caption)
                        .buttonStyle(.link)
                    }
                }
            }

            Section("Aktualisierung") {
                Picker("Alle", selection: Binding(
                    get: { settings.refreshIntervalMinutes },
                    set: {
                        settings.refreshIntervalMinutes = $0
                        UsageMonitor.shared.poll()
                    }
                )) {
                    ForEach(Self.intervals, id: \.self) { minutes in
                        Text(minutes == 1 ? "1 Minute" : "\(minutes) Minuten").tag(minutes)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Menüleiste") {
                Toggle("Wochennutzung zusätzlich anzeigen (z. B. „🦙 2% · 1%“)",
                       isOn: $settings.showWeeklyInMenuBar)
            }

            Section("Benachrichtigungen") {
                Toggle("Bei Schwellenüberschreitung benachrichtigen", isOn: Binding(
                    get: { settings.notificationsEnabled },
                    set: { newValue in
                        settings.notificationsEnabled = newValue
                        if newValue {
                            Task { await Notifier.requestAuthorization() }
                        }
                    }
                ))
                Picker("Schwellen", selection: $settings.thresholds) {
                    Text("50 · 75 · 90 · 100 %").tag([50.0, 75.0, 90.0, 100.0])
                    Text("75 · 90 · 100 %").tag([75.0, 90.0, 100.0])
                    Text("90 · 100 %").tag([90.0, 100.0])
                }
                .pickerStyle(.menu)
            }

            Section {
                Toggle("Bei Anmeldung starten", isOn: Binding(
                    get: { launchAtLogin },
                    set: {
                        settings.launchAtLoginEnabled = $0
                        launchAtLogin = settings.launchAtLoginEnabled
                    }
                ))
            } header: {
                Text("Allgemein")
            } footer: {
                Text("OllaStat ist ein inoffizielles Werkzeug und scrape die angemeldete Seite ollama.com/settings. Es gibt keine offizielle Ollama-API für Nutzungswerte — der Abruf kann brechen, wenn Ollama die Seite ändert. Dein Cookie wird nur lokal im Schlüsselbund gespeichert und ausschließlich an ollama.com gesendet.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 500)
        .onAppear { launchAtLogin = settings.launchAtLoginEnabled }
        .sheet(isPresented: $showLogin) {
            LoginSheetView()
        }
    }
}