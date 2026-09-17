# Releases erstellen

So wird ein neues OllaStat-Release veröffentlicht.

## Standard-Weg: Tag pushen

Der Workflow `.github/workflows/release.yml` erledigt alles Automatische:

1. Release-Build (`xcodebuild -configuration Release`)
2. DMG bauen (`OllaStat-<version>.dmg`, mit Applications-Symlink)
3. DMG mit Sparkle EdDSA signieren (falls Secret vorhanden)
4. `appcast.xml` aktualisieren und auf `main` committen
5. GitHub Release mit Notes aus `CHANGELOG.md` erstellen
6. Homebrew-Tap bumpen (falls `TAP_TOKEN` vorhanden)

```bash
# 1. Version bumpen (project.yml: CFBundleShortVersionString + CFBundleVersion)
# 2. CHANGELOG.md mit "## <version> – <datum>" Sektion füllen
# 3. Committen und taggen:
git add -A
git commit -m "Release v0.1.2"
git tag v0.1.2
git push origin main --tags
```

Voraussetzungen dafür:
- `CHANGELOG.md` enthält eine Sektion `## 0.1.2` (daraus werden die Release-Notes extrahiert)
- `project.yml` hat `CFBundleShortVersionString: "0.1.2"` und erhöhte `CFBundleVersion`

## Erforderliche Secrets (Repo-Settings → Secrets → Actions)

| Secret | Zweck | Pflicht? |
|---|---|---|
| `SPARKLE_ED_PRIVATE_KEY` | Base64-Export des Sparkle-EdDSA-Private-Keys → signierte DMGs im AppCast | Empfohlen, sobald Updates ausgerollt werden |
| `TAP_TOKEN` | GitHub-PAT (Scope `repo`) für Pushes auf `diceone/homebrew-tap` → automatischer Cask-Bump | Optional, sonst manueller Bump |
| `MACOS_CERTIFICATE` | Base64 der **Developer ID Application**-.p12 → signiert die App (Hardened Runtime) | Optional, ohne bleibt die App unsigniert (Gatekeeper-Warnung) |
| `MACOS_CERTIFICATE_PWD` | Passwort der .p12-Datei | Mit MACOS_CERTIFICATE |
| `APPLE_TEAM_ID` | 10-stellige Team-ID (für Keychain-/Cert-Referenz) | Mit MACOS_CERTIFICATE |
| `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`, `NOTARY_API_KEY` | App-Store-Connect-API-Key → notarisiert + stapelt die DMG | Optional, ohne keine Notarisierung |

## Signierung & Notarisierung

Ohne Signierung zeigt macOS beim ersten Start „nicht verifiziert"-Warnungen
(Rechtsklick → Öffnen bzw. `xattr`). Mit Developer-ID-Zertifikat + Notarisierung
läuft die App wie jede Mac-App aus dem Internet — und Brew-Installationen sind sauber verifizierbar.

### 1. Zertifikat erstellen (einmalig)

1. Mitgliedschaft im **Apple Developer Program** ($99/Jahr, [developer.apple.com](https://developer.apple.com/programs))
2. Xcode → Settings → Accounts → Team wählen → **Manage Certificates** → `+` → **Developer ID Application**
3. Schlüsselbundzugriff: Zertifikat + privater Schlüssel exportieren (.p12, mit Passwort)
4. Als Secrets hinterlegen:

```bash
base64 -i DeveloperIDApplication.p12 | pbcopy   # → GitHub-Secret MACOS_CERTIFICATE
# Passwort → MACOS_CERTIFICATE_PWD, Team-ID (Xcode → Accounts) → APPLE_TEAM_ID
```

### 2. Notarisierungs-Key erstellen (einmalig)

1. [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → Users and Access → Integrations → **App Store Connect API** → Team Keys → Neuen Key generieren (Rolle egal, Notarisierung braucht keine)
2. `.p8`-Datei herunterladen (**nur einmal möglich!**) + Key-ID und Issuer-ID notieren
3. Secrets: `NOTARY_API_KEY` = `base64 -i AuthKey_XXX.p8`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`

Die CI signiert die App (Developer ID, Hardened Runtime, Timestamp), notarisiert
die DMG via `notarytool --wait` und stapelt sie (`stapler staple`). Danach
signiert Sparkle den AppCast-Eintrag — alles automatisch beim Tag-Push.

### 3. Lokal testen

```bash
codesign --force --options runtime --timestamp \
  --sign "Developer ID Application" --entitlements OllaStat/App/OllaStat.entitlements \
  build/OllaStat.app
codesign --verify --strict build/OllaStat.app && codesign -dv build/OllaStat.app
spctl assess --type execute build/OllaStat.app   # „accepted" nach Notarisierung

### Sparkle-Keys erzeugen

```bash
# generate_keys aus dem Sparkle-Release laden (Sparkle-for-Swift-Package-Manager.zip → bin/)
./generate_keys --account ollastat
# → Public Key ausgeben lassen (SUPublicEDKey) und in project.yml (Info-Properties) eintragen
./generate_keys -p --account ollastat
# → Private Key exportieren (Datei enthält base64 — genau dieser Inhalt ist das Secret):
./generate_keys -x sparkledsa_priv.txt --account ollastat
gh secret set SPARKLE_ED_PRIVATE_KEY < sparkledsa_priv.txt
```

Der **Private Key ist das Signier-Geschäft**: Wer ihn hat, kann Updates unterschieben.
Niemals committen! Nur als GitHub-Secret und lokal im Schlüsselbund sichern.

Sobald `SUPublicEDKey` in der App steht, akzeptiert Sparkle nur noch EdDSA-signierte
Updates — vorher signierte/unsignierte AppCast-Einträge ohne Public Key werden ignoriert.

### Tap manuell bumpen (falls kein TAP_TOKEN)

```bash
cd ../homebrew-tap
# Casks/ollastat.rb: version + sha256 aktualisieren
shasum -a 256 OllaStat-0.1.2.dmg   # sha vom Release-Asset herunterladen
git commit -am "OllaStat 0.1.2" && git push
brew fetch --cask diceone/tap/ollastat   # verifizieren
```

## CI-Tests vor dem Release

Jeder Push/PR läuft durch `.github/workflows/ci.yml` (Build + Unit-Tests auf
macos-latest). Lokal vorher:

```bash
xcodegen generate
xcodebuild -project OllaStat.xcodeproj -scheme OllaStat test
```