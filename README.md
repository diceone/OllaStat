# OllaStat

🦙 Eine native **macOS-Menüleisten-App** (SwiftUI, `MenuBarExtra`), die die Token-/Request-Nutzung deines **Ollama Cloud**-Accounts live in der Menüleiste anzeigt.

![Screenshot-Platzhalter: Menüleiste mit „🦙 2%“ und Dropdown mit Fortschrittsbalken]

## Features

- **Menüleisten-Label** mit Live-Werten, z. B. `🦙 42%` (5h-Fenster) und optional `🦙 42% · 12%` (5h + Woche)
- **Dropdown-Panel**:
  - 5-Stunden-Fenster und Wochennutzung mit Fortschrittsbalken (grün/orange/rot je nach Auslastung)
  - „Resets in …“-Countdown pro Fenster
  - Requests pro Modell (wie auf ollama.com/settings)
- **Automatisches Polling** (1–60 Minuten, Standard 5) + manueller Refresh-Button
- **Schwellen-Benachrichtigungen** (macOS-Mitteilungen) bei z. B. 50/75/90/100 %
- **Cookie-Verwaltung** über den macOS-Schlüsselbund mit eingebauter Anleitung und Validierung
- **Start bei Anmeldung** (SMAppService), Snapshot-Cache für Sofortanzeige nach Relaunch

## Warum kein „richtiges“ API-Token?

Ollama bietet aktuell **keine offizielle API** für Account-Nutzungswerte (siehe [ollama/ollama#15132](https://github.com/ollama/ollama/issues/15132) und [#12532](https://github.com/ollama/ollama/issues/12532)). Die Werte werden serverseitig auf der angemeldeten Seite [ollama.com/settings](https://ollama.com/settings) gerendert. OllaStat ruft diese Seite mit deinem **Session-Cookie `__Secure-session`** ab und parst die Maschinen-Marker (`data-usage-track`, `data-usage-segment`, `data-time`).

> ⚠️ **Disclaimer:** Inoffizielles Werkzeug, nicht mit Ollama verbunden. Der Abruf kann brechen, wenn Ollama die Settings-Seite ändert. Der Cookie ermöglicht vollen Zugriff auf deine Sitzung — OllaStat speichert ihn ausschließlich lokal im Schlüsselbund und sendet ihn **nur** an ollama.com.

## Lizenz

OllaStat steht unter der **[PolyForm Noncommercial License 1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0)**:

- ✅ **Erlaubt:** Kopieren, Modifizieren, Weitergeben und Nutzung für persönliche/nicht-kommerzielle Zwecke (Hobby, Studium, Forschung, gemeinnützige Organisationen …)
- ❌ **Verboten:** Kommerzielle Nutzung — mit der Software darf niemand Geld verdienen (Verkauf, SaaS, bezahlte Distribution, Nutzung im kommerziellen Arbeitsumfeld)
- Kommerzielle Rechte bleiben beim Autor. Anfragen für kommerzielle Lizenzen bitte über [GitHub Issues](https://github.com/diceone/OllaStat/issues)

## Setup

**Fertige Builds gibt es in den [GitHub Releases](https://github.com/diceone/OllaStat/releases) (DMG) oder per Homebrew:**

```bash
brew install --cask diceone/tap/ollastat
```

Die App ist nicht notarisiert — beim ersten Start ggf. Rechtsklick → *Öffnen* oder `xattr -dr com.apple.quarantine /Applications/OllaStat.app`.

1. **In-App-Anmeldung:** OllaStat → Menüleiste → **Einstellungen** → **„Bei ollama.com anmelden …"** → im eingebetteten Browserfenster anmelden (z. B. mit GitHub). OllaStat fängt das Session-Cookie automatisch ab, prüft es und speichert es im Schlüsselbund — nichts kopieren.

Der Cookie läuft nach ca. 3 Monaten ab — dann erscheint `🦙 !` in der Menüleiste und ein Klick auf „Einstellungen öffnen" bringt dich direkt zur erneuten Anmeldung.

## Build

Voraussetzungen: Xcode 15+, [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
xcodegen generate
xcodebuild -project OllaStat.xcodeproj -scheme OllaStat -configuration Debug build
open build/Debug/OllaStat.app            # bzw. DerivedData-Pfad
```

Tests:

```bash
xcodebuild -project OllaStat.xcodeproj -scheme OllaStat test
```

In Xcode: `OllaStat.xcodeproj` öffnen und das Schema `OllaStat` starten.

## Projektstruktur

```
OllaStat/
├── App/OllaStatApp.swift      # @main, MenuBarExtra, Settings-Fenster
├── Views/PanelView.swift      # Dropdown mit Fenstern/Modellen
├── Views/LoginView.swift      # Eingebetteter WKWebView-Login (Cookie-Automatik)
├── Views/SettingsView.swift   # Cookie-Paste, Intervall, Benachrichtigungen
├── Core/HTMLParser.swift      # Mini-HTML-DOM (selbstständig, keine Dependencies)
├── Core/UsageParser.swift     # Settings-Markup → UsageData
├── Core/UsageFetcher.swift    # Abruf mit Cookie + Session-Expired-Erkennung
├── Core/UsageMonitor.swift    # Polling, Schwellen-Tracker, Menü-Label
├── Core/KeychainStore.swift   # Cookie im Schlüsselbund
└── Core/AppSettings.swift     # UserDefaults + Snapshot-Persistenz
```

Die Parser-Tests laufen gegen ein Fixture der echten ollama.com/settings-Struktur (`Tests/Fixtures/settings.html`).