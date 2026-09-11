# Growmont CRM Self-Update System — Integration Guide

## Files added

### Flutter (`flutterapp/`)
```
lib/core/updater/version_constants.dart
lib/core/updater/update_model.dart
lib/core/updater/update_service.dart
lib/core/updater/update_notifier.dart
lib/core/updater/update_dialog.dart
lib/features/profile/widgets/update_card.dart
lib/features/profile/widgets/data_location_card.dart
lib/features/profile/widgets/sync_status_card.dart
```

### Modified Flutter files
```
lib/main.dart                              — starts UpdateNotifier.checkForUpdate()
lib/features/profile/profile_screen.dart   — adds the "System" tab
pubspec.yaml                               — package_info_plus dependency
```

### Installer project (repo root)
```
installer/growmont_installer.iss
installer/build_release.ps1
installer/README.md
```

---

## Update source: GitHub Releases API

Update information is sourced entirely from the GitHub Releases REST API —
there is no `latest.json` metadata file to maintain:

```
GET https://api.github.com/repos/{owner}/{repo}/releases/latest
```

The owner/repo pair is declared once in
`lib/core/updater/version_constants.dart` (`kGitHubRepoOwner`,
`kGitHubRepoName`) and the endpoint is built from those constants — nothing
else in the codebase should hardcode the repo path.

There is nothing to "update" between releases beyond publishing the GitHub
release itself with a correctly-named installer asset
(`Growmont-Setup-<version>.exe`, plus its `.sha256` sibling) — see
`RELEASE.md` for the full flow and naming convention.

---

## Build the installer

```powershell
.\installer\build_release.ps1
```

Produces `installer\Output\Growmont-Setup-<version>.exe` and its
`.sha256` sibling. See `installer/README.md` for prerequisites and options.

---

## Release flow

`pubspec.yaml`'s `version:` field is the single source of truth for the app
version — there is no separate version constant to keep in sync. See
`RELEASE.md` for the full, required build procedure (including why
`flutter clean` is mandatory on Windows and how to verify the built
`growmont_crm.exe`).

1. Bump `version:` in `flutterapp/pubspec.yaml`.
2. Run `installer\build_release.ps1` (see `RELEASE.md`).
3. Publish a GitHub release tagged like `v1.1.0` on the release repo.
4. Upload `Growmont-Setup-1.1.0.exe` and `Growmont-Setup-1.1.0.exe.sha256`
   to that release. The in-app updater discovers it automatically via the
   GitHub Releases API — no metadata file to update.

---

## How the update actually runs

`UpdateService.downloadUpdate()` downloads the installer `.exe` directly
(no zip, no extraction step). `UpdateService.launchUpdaterAndExit()` then
runs it with `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-` and exits the
running app. Inno Setup's `CloseApplications`/`CloseApplicationsFilter`
(see `installer/growmont_installer.iss`) closes any still-running instance
before copying files, and its `[Run]` section's `skipifnotsilent` entry
relaunches `growmont_crm.exe` once the silent install finishes. There is no
separate `updater.exe` helper process — the installer itself does the whole
job.

## Data safety

The installer only writes inside `{localappdata}\Programs\GrowmontCRM` — the
install folder. It never references, packages, or deletes anything under
`%AppData%\Roaming\...\GrowmontCRM\...`, so `growmont.db` (and its
timestamped backups) are never touched by an install, update, or uninstall.
See `LOCAL_FIRST.md` for the full storage layout and why this matters.
