# Changelog

Alle nennenswerten Änderungen an OllaStat werden hier dokumentiert.
Format angelehnt an [Keep a Changelog](https://keepachangelog.com/de/1.1.0/).

## 0.1.1 – 2026-09-13

### Neu
- **Auto-Updates via Sparkle**: automatische Update-Prüfung beim Start + „Nach Updates suchen …“ in den Einstellungen (AppCast: `appcast.xml`)
- **Natives Menüleisten-Icon**: Llama als Template-Icon (passt sich Hell-/Dunkelmodus an) neben der Prozent-Anzeige
- **CI/CD**: GitHub Actions — Tests bei jedem Push/PR (`ci.yml`), automatisches Release mit DMG + AppCast bei Tag-Push (`release.yml`)
- **Tests für UsageFetcher**: Redirects zu `/signin`, HTTP-Fehler, Cookie/User-Agent-Header (MockURLProtocol)

### Geändert
- Lizenz (PolyForm Noncommercial 1.0.0) wird im App-Bundle mitgeliefert

## 0.1.0 – 2026-09-13

### Neu
- Erstes Release
- Token-/Request-Verbrauch des Ollama-Cloud-Accounts in der macOS-Menüleiste (5h- und Wochen-Fenster)
- Automatischer Abruf über `ollama.com/settings` mit dem Session-Cookie
- **In-App-Anmeldung**: Login bei ollama.com direkt in der App (WKWebView), Cookie wird sicher im Schlüsselbund gespeichert
- Konfigurierbare Warn-Schwellen (50/75 %) mit macOS-Benachrichtigungen
- Aktualisierungsintervall einstellbar, Wochen-Anzeige in der Menüleiste optional
- Start bei Anmeldung (Launch-at-Login)
- Llama-App-Icon
- Homebrew-Tap: `brew install --cask diceone/tap/ollastat`
- PolyForm-Noncommercial-1.0.0-Lizenz