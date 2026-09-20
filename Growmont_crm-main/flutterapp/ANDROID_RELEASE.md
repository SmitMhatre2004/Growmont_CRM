# Growmont CRM Android Release Procedure

The Android counterpart to [`RELEASE.md`](RELEASE.md). Same single source
of truth (`pubspec.yaml`), same release repo, same GitHub release — but
Android adds two hard rules that Windows does not have, and one artifact
that must never be lost. Read "The signing key" before your first release.

## The signing key

Every Android APK is cryptographically signed, and **Android will only
install an update over an existing app if both are signed with the same
key.** Not a policy — the package installer enforces it. A mismatch fails
with `INSTALL_FAILED_UPDATE_INCOMPATIBLE` ("App not installed"), and the
only way forward for that user is to uninstall first.

Uninstalling deletes the app's private storage, which is where
`growmont.db` lives. So a lost or changed signing key means **every
installed user loses their local CRM data.** There is no recovery path,
no support channel, and no override. This is why the key matters more
here than it would on the Play Store, where Google holds it for you.

Two files carry it:

| File | What it is |
| --- | --- |
| `android/growmont-release.jks` | The private key. 4096-bit RSA, valid 10,000 days. |
| `android/key.properties` | Its password and alias, in plaintext. |

Both are gitignored and will **not** arrive with a clone. Back them up
somewhere that survives this laptop — a password manager's file
attachment, or an encrypted archive somewhere durable. Not a public repo,
not a plain cloud folder.

`android/app/build.gradle.kts` fails the build outright if
`key.properties` is missing, rather than falling back to the debug key.
That fallback is the Flutter template default and it is a trap: the debug
keystore is generated per-machine and uses a publicly known password, so a
debug-signed APK cannot be updated from any other machine and can be
forged by anyone.

### If a debug-signed APK was ever installed

Any APK built before this signing setup existed was debug-signed. Those
installs cannot receive a release-signed update — testers must uninstall
the old build first. This is a one-time cost, and only for pre-release
test devices. Once everyone is on a release-signed build, updates work
normally forever.

## The two version rules

`pubspec.yaml`'s `version: <name>+<code>` supplies both halves:

```yaml
version: 1.1.0+2
#        ^^^^^ versionName    ^ versionCode
```

**Rule A — versionCode must strictly increase.** Android uses only
versionCode to decide whether an APK is an upgrade. Equal reinstalls
without being an update; lower is rejected as a downgrade. Windows ignores
this number entirely, so it is easy to forget.

**Rule B — versionName must not repeat.** `UpdateService._isNewer()`
compares versionName strings. Re-publishing `1.1.0` means every existing
install compares `1.1.0` against `1.1.0`, finds nothing newer, and is
never prompted — on **both** platforms. The release silently reaches only
people installing fresh. If you need to ship a fix to an already-published
version, bump the patch: `1.1.0` → `1.1.1`.

Both rules are enforced by the build script against
`android/released_version_codes.txt`, a committed ledger of what has
already shipped. It refuses the build rather than warning. Rebuilding the
most recent entry unchanged is allowed, so a failed device test does not
force a version bump.

## Building a release

```powershell
.\installer\build_android_release.ps1
```

From anywhere; paths resolve relative to the script. It performs:

1. Read and validate the version from `pubspec.yaml` (rejects a missing
   `+build` — a bare `1.1.0` would silently become versionCode 1).
2. Enforce Rules A and B against the ledger.
3. `flutter clean` → `flutter pub get` → `flutter build apk --release`.
4. Verify the built APK's real versionCode/versionName, read from
   Gradle's `output-metadata.json`, match `pubspec.yaml`. This is the
   Android equivalent of the Windows FileVersion check and catches the
   same stale-build problem.
5. Verify the APK's signing certificate fingerprint matches
   `growmont-release.jks`. This is what would catch a debug-signed build
   before it reaches anyone.
6. Write `installer/Output/Growmont-CRM-<version>.apk` and its `.sha256`.
7. Append to the ledger.

Flags: `-AllowSameVersionName` (rebuild an unpublished artifact under a
used name) and `-SkipSignatureCheck` (not recommended — it disables the
check in step 5).

A single universal APK is produced rather than `--split-per-abi`: the
website download is one link, and asking a user to identify their CPU
architecture is not a reasonable step. The size cost is accepted.

## Asset naming is load-bearing

`UpdateService` finds the release asset by name, using the constants in
`lib/core/updater/version_constants.dart`:

| Platform | Asset name |
| --- | --- |
| Windows | `Growmont-Setup-<version>.exe` |
| Android | `Growmont-CRM-<version>.apk` |

A differently-named asset is **silently invisible** to the updater — it
reports "no update available" rather than erroring, so a typo here
produces a release nobody is offered. The two prefixes differ so neither
platform can ever select the other's artifact.

## Publishing

One GitHub release serves both platforms. On
[CruciaTos/GrowmontCRM_Release](https://github.com/CruciaTos/GrowmontCRM_Release):

1. Build both: `installer\build_release.ps1` and
   `installer\build_android_release.ps1`.
2. Install the APK on a real device and confirm it opens, logs in, and
   syncs. The signature and version checks cannot catch a runtime
   regression.
3. Create a release tagged `v<version>`, matching `pubspec.yaml` exactly.
4. Upload all four files from `installer/Output/`:
   - `Growmont-Setup-<version>.exe` + `.sha256`
   - `Growmont-CRM-<version>.apk` + `.sha256`
5. Publish. Both platforms pick it up on their next check.
6. Commit the updated `android/released_version_codes.txt`.

## The website download button

GitHub serves a stable URL for the newest release, so the button does not
need updating per release:

```
https://github.com/CruciaTos/GrowmontCRM_Release/releases/latest/download/Growmont-CRM-<version>.apk
```

The `<version>` in the filename still changes, so for a button that never
needs touching, link to the release page itself and let the user pick:

```
https://github.com/CruciaTos/GrowmontCRM_Release/releases/latest
```

Browsers warn before downloading an APK, and Android warns again at
install. That is normal for any app distributed outside the Play Store.
Worth saying so next to the button, or users will assume something is
wrong.

## How in-app updates work on Android

Both platforms read the same GitHub release and resolve their own asset.
The install step is where they diverge:

- **Windows** runs the Inno Setup installer silently and exits.
- **Android cannot.** No API lets a sideloaded app install an APK without
  the user confirming on a system-drawn screen — one that existed would be
  a complete device-compromise vector. The user taps through the system
  installer, and the app does **not** call `exit(0)`: Android stops the
  process itself when replacing the APK.

Additionally, Android 8+ requires the user to grant "install unknown apps"
to Growmont CRM, once, and it is off by default. `MainActivity.kt` checks
this up front and sends the user to that exact settings page. Without that
check the update button would appear to do nothing at all.

Implementation: `MainActivity.kt` (method channel + FileProvider),
`UpdateService._installApkAndroid`, and the `REQUEST_INSTALL_PACKAGES`
permission plus `file_paths.xml` in the Android manifest.

## Why not Firebase Remote Config for version checks

It would add a second place that declares the current version, which
[`RELEASE.md`](RELEASE.md) rules out for good reason: the two sources
drift, and the failure is silent — the app reports a version that does not
match what is actually published. The GitHub release already is the source
of truth, and both platforms already read it. Nothing to add.

## Data safety

Android app data (including `growmont.db`) lives in the app's private
storage and is preserved across updates **as long as the signing key does
not change**. See "The signing key". The FileProvider in
`file_paths.xml` is deliberately scoped to the cache directory alone, so
the database is never exposed to the package installer or any other app.
