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