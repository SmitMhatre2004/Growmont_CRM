# Growmont CRM Installer & Release Automation

This folder contains the packaging pipeline: the Inno Setup installer
script and the PowerShell script that drives the full release build. For
the app-side update mechanism (how `growmont_crm.exe` discovers and
downloads releases), see `../flutterapp/RELEASE.md` and
`../flutterapp/UPDATE_SYSTEM_README.md` — this folder only covers turning a
Release build into `Growmont-Setup-<version>.exe`.

## Files

| File                       | Purpose                                                    |
|-----------------------------|-------------------------------------------------------------|
| `growmont_installer.iss`   | Inno Setup 6 script. Defines the per-user installer.        |
| `build_release.ps1`        | End-to-end release pipeline (build → verify → package → checksum). |

## Prerequisites

- Flutter SDK (with Windows desktop support enabled) and Dart SDK on `PATH`.
- [Inno Setup 6](https://jrsoftware.org/isinfo.php) installed. `build_release.ps1`
  looks for `ISCC.exe` on `PATH`, then under the two standard
  `Program Files` locations. If it's installed somewhere else, pass
  `-IsccPath`.
- Windows, since this packages a Windows desktop build.

## Usage

From a PowerShell prompt, from anywhere in the repo:

```powershell
.\installer\build_release.ps1
```

This runs the full pipeline described in `flutterapp/RELEASE.md`:

1. Reads `version:` from `flutterapp/pubspec.yaml` (e.g. `1.1.0+1` →
   installer version `1.1.0`).
2. `flutter clean`
3. `flutter pub get`
4. `flutter build windows --release`
5. Verifies the built `growmont_crm.exe`'s embedded File version matches
   `pubspec.yaml` — aborts if they disagree instead of packaging a stale
   build (this automates the manual Explorer-properties check
   `RELEASE.md` documents).
6. Runs Inno Setup against `growmont_installer.iss`, producing:

   ```
   installer\Output\Growmont-Setup-<version>.exe
   ```
7. Writes `installer\Output\Growmont-Setup-<version>.exe.sha256` — a plain
   text file with the installer's SHA-256 digest. `UpdateService`'s
   checksum verification looks for this exact sibling file next to the
   release asset and switches on automatically once it's published.

Upload **both files** to the GitHub release tagged `v<version>` — the
installer's filename convention is what the in-app updater matches against
(see `RELEASE.md`, "How the app discovers updates").

### Options

```powershell
# Skip the embedded-version check (fast local iteration only — do not use
# for a build you intend to publish)
.\installer\build_release.ps1 -SkipVerify

# Point at a non-standard Inno Setup install location
.\installer\build_release.ps1 -IsccPath "D:\Tools\Inno Setup 6\ISCC.exe"
```

### Building the installer only (build already done)

If you've already run steps 1–4 yourself and just want to (re)compile the
installer:

```powershell
iscc installer\growmont_installer.iss /DMyAppVersion=1.1.0
```

This uses the script's default `ReleaseDir`
(`flutterapp\build\windows\x64\runner\Release`, relative to `installer\`).
If your Flutter build landed under the older
`flutterapp\build\windows\runner\Release` path instead, override it
explicitly:

```powershell
iscc installer\growmont_installer.iss /DMyAppVersion=1.1.0 /DReleaseDir=../flutterapp/build/windows/runner/Release
```

(Use forward slashes in `/DReleaseDir` — see the comment at the top of
`growmont_installer.iss` for why.)

## What the installer does and does not touch

- Installs per-user to `{localappdata}\Programs\GrowmontCRM` — no admin
  rights, no UAC prompt.
- Supports in-place upgrades: the AppId is fixed
  (`7B3F1A62-9C48-4E1D-BF06-2A5D8C4E9F13`), so re-running a newer installer
  finds and overwrites the existing install rather than creating a second
  copy. **Do not change this AppId** — doing so after the first release
  breaks in-place upgrades for everyone already installed.
- Closes a running `growmont_crm.exe` automatically before copying files
  (Inno Setup's native Restart Manager integration — `CloseApplications`),
  rather than any custom process-killing code.
- Never references, packages, or deletes anything under
  `%AppData%\Roaming\...\GrowmontCRM\...` (where `growmont.db` and other
  persistent user data live, via `AppPaths`). The installer's own
  uninstall step only ever removes `{localappdata}\Programs\GrowmontCRM` —
  a completely separate directory tree.
- Supports the standard silent-install switches out of the box:
  `/VERYSILENT`, `/SUPPRESSMSGBOXES`, `/NORESTART`, `/SP-`.

## Output

`installer\Output\` holds compiled installers and is git-ignored; it's
build output, not source.
