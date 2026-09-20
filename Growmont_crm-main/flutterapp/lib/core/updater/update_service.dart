// lib/core/updater/update_service.dart

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'update_model.dart';
import 'version_constants.dart';

class UpdateService {
  UpdateService._();

  /// Returns the current installed version, read from the PE version
  /// resources baked into the running executable at compile time — sourced
  /// directly from `pubspec.yaml`'s `version:` field via Flutter's Windows
  /// build tooling (see RELEASE.md).
  static Future<String> getCurrentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version.trim();
  }

  /// Checks GitHub Releases for the latest published Growmont CRM release.
  ///
  /// This never throws. If GitHub is unreachable, no release has been
  /// published yet, the release has no matching installer asset, or the
  /// response can't be parsed, this returns a graceful "no update
  /// information available" [UpdateInfo] (`updateAvailable: false`) instead
  /// of crashing or surfacing an error banner to the user.
  static Future<UpdateInfo> checkForUpdate() async {
    final currentVersion = await getCurrentVersion();
    final release = await _fetchLatestRelease();

    if (release == null) {
      return _noUpdateInfo(currentVersion);
    }

    return UpdateInfo(
      currentVersion: currentVersion,
      latestVersion: release.version,
      updateAvailable: _isNewer(release.version, currentVersion),
      message: release.message,
      // GitHub Releases has no concept of a "force this update" flag.
      // Forced updates aren't supported by this source; a future phase
      // could encode that signal in the release itself (e.g. a tag/title
      // marker or a required-version file) if it's needed again.
      force: false,
      downloadUrl: release.downloadUrl,
    );
  }

  /// [UpdateInfo] used whenever release information couldn't be obtained.
  /// `latestVersion` is set to `currentVersion` so nothing downstream
  /// mistakenly reports an update as available.
  static UpdateInfo _noUpdateInfo(String currentVersion) {
    return UpdateInfo(
      currentVersion: currentVersion,
      latestVersion: currentVersion,
      updateAvailable: false,
      message: 'No update information available.',
      force: false,
      downloadUrl: '',
    );
  }

  /// Fetches and parses the latest GitHub release, extracting the version
  /// (from `tag_name`) and the installer download URL (from `assets[]`).
  ///
  /// Returns `null` — never throws — if anything goes wrong: network
  /// failure, non-200 response (including 404 when no release exists yet),
  /// malformed JSON, a missing/empty `tag_name`, or no asset matching the
  /// installer naming convention.
  static Future<_LatestRelease?> _fetchLatestRelease() async {
    try {
      final response = await http.get(
        Uri.parse(kLatestReleaseApiUrl),
        headers: const {
          // GitHub requires a User-Agent on API requests; omitting it can
          // result in a 403 even for unauthenticated public endpoints.
          'User-Agent': '$kGitHubRepoName-app',
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;

      final tagName = (decoded['tag_name'] as String?)?.trim();
      if (tagName == null || tagName.isEmpty) return null;
      final version = _stripLeadingV(tagName);
      if (version.isEmpty) return null;

      final assets = decoded['assets'];
      if (assets is! List) return null;

      String? downloadUrl;
      for (final asset in assets) {
        if (asset is! Map<String, dynamic>) continue;
        final name = asset['name'] as String?;
        final url = asset['browser_download_url'] as String?;
        if (name == null || url == null) continue;
        if (_isInstallerAsset(name)) {
          downloadUrl = url;
          break;
        }
      }
      if (downloadUrl == null) return null;

      return _LatestRelease(
        version: version,
        downloadUrl: downloadUrl,
        // Release notes (`body`) can be long, markdown-formatted, or
        // absent — not suitable to drop straight into the compact update
        // dialog, so a short fixed message is used instead.
        message: 'A new version is available.',
      );
    } catch (_) {
      return null;
    }
  }

  /// Strips a single optional leading "v"/"V" from a release tag.
  /// `v1.1.0` -> `1.1.0`; `1.1.0` -> `1.1.0`.
  static String _stripLeadingV(String tagName) {
    if (tagName.isEmpty) return tagName;
    final first = tagName[0];
    return (first == 'v' || first == 'V') ? tagName.substring(1) : tagName;
  }

  /// The asset-name prefix/extension pair this platform's installer uses.
  ///
  /// A single GitHub release publishes both platforms' artifacts side by
  /// side, so the running platform decides which one is "the" installer.
  static (String prefix, String extension) get _assetNaming =>
      Platform.isAndroid
          ? (kAndroidAssetPrefix, kAndroidAssetExtension)
          : (kInstallerAssetPrefix, kInstallerAssetExtension);

  /// Matches the release asset that is the actual installer for the running
  /// platform — `Growmont-Setup-1.2.0.exe` on Windows,
  /// `growmont-1.2.0.apk` on Android. Explicitly excludes GitHub's
  /// auto-generated source archives, the `.sha256` sidecars, and the other
  /// platform's artifact.
  static bool _isInstallerAsset(String assetName) {
    final lower = assetName.toLowerCase();
    if (lower.endsWith('.zip') || lower.endsWith('.tar.gz')) return false;
    // The checksum sidecar ends in the installer's own name plus
    // `.sha256`, so it would otherwise pass a naive prefix test.
    if (lower.endsWith('.sha256')) return false;
    final (prefix, extension) = _assetNaming;
    return assetName.startsWith(prefix) && lower.endsWith(extension);
  }

  /// Downloads the installer referenced by [downloadUrl] — the
  /// `Growmont-Setup-{version}.exe` or `growmont-{version}.apk` asset from
  /// the GitHub Releases lookup — into [getTemporaryDirectory], preserving
  /// its original filename, and returns the local path on success.
  ///
  /// On Android that directory is the app's own cache dir, which is why no
  /// storage permission is involved and none of the scoped-storage rules
  /// apply: nothing here writes to shared storage or to
  /// `/storage/emulated/0/Download`. It is also the only path the
  /// FileProvider in AndroidManifest.xml exposes, so the package installer
  /// can read the APK and nothing else. The file saved here is handed
  /// directly to [launchUpdaterAndExit], which runs it as a real Inno
  /// Setup installer — no zip extraction step.
  ///
  /// Throws a descriptive [Exception] on any failure so the notifier can
  /// surface the real reason to the user instead of a generic message.
  static Future<String> downloadUpdate(
    String downloadUrl,
    void Function(double progress) onProgress,
  ) async {
    final client = http.Client();
    try {
      final tmpDir = await getTemporaryDirectory();
      final fileName = _installerFileNameFrom(downloadUrl);
      final installerPath =
          '${tmpDir.path}${Platform.pathSeparator}$fileName';

      final request = http.Request('GET', Uri.parse(downloadUrl));
      final streamedResponse = await client.send(request);

      if (streamedResponse.statusCode != 200) {
        throw Exception(
            'Download server returned ${streamedResponse.statusCode}');
      }

      final contentLength = streamedResponse.contentLength ?? 0;
      var received = 0;
      var lastPercentReported = -1;

      final file = File(installerPath);
      final sink = file.openWrite();

      try {
        await for (final chunk in streamedResponse.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (contentLength > 0) {
            // Reported per whole percent, not per chunk. A 66 MB APK
            // arrives in thousands of chunks and each one would otherwise
            // rebuild the update dialog — on a phone that is enough
            // UI-thread work to make the download itself look stalled, and
            // the progress bar cannot render finer than a percent anyway.
            final percent = (received * 100) ~/ contentLength;
            if (percent != lastPercentReported) {
              lastPercentReported = percent;
              onProgress(received / contentLength);
            }
          }
        }
      } finally {
        await sink.close();
      }

      final written = await file.length();
      if (written == 0) {
        throw Exception('Downloaded file is empty — the URL may be invalid.');
      }

      // A connection dropped mid-transfer ends the stream without raising,
      // leaving a truncated file that is not empty and so passes the check
      // above. Android's package installer reports that as a flat "App not
      // installed" with no reason given, so it is compared against
      // Content-Length here, where the real cause can still be named.
      if (contentLength > 0 && written != contentLength) {
        await _deleteQuietly(file);
        throw Exception(
          'Download incomplete — expected $contentLength bytes, got '
          '$written. Check the connection and try again.',
        );
      }

      // Checksum verification extension point — see
      // _verifyChecksumIfAvailable for details. No-op until the release
      // pipeline (installer/build_release.ps1) publishes a `.sha256`
      // sibling asset.
      await _verifyChecksumIfAvailable(client, downloadUrl, file);

      return installerPath;
    } catch (e) {
      throw Exception('Download failed: $e');
    } finally {
      client.close();
    }
  }

  /// Derives the on-disk filename for the downloaded installer from
  /// [downloadUrl], preserving the original asset filename (e.g.
  /// `Growmont-Setup-1.2.0.exe`) instead of a generic hardcoded name — the
  /// installer's own name is what Windows/Inno Setup will show in any
  /// UAC-less "Open File" prompts and logs, so keeping it intact matters.
  ///
  /// GitHub release asset download URLs always end in the asset's literal
  /// filename, so this only falls back to a synthesized name if that ever
  /// stops being true (e.g. a malformed URL).
  static String _installerFileNameFrom(String downloadUrl) {
    final segments = Uri.parse(downloadUrl).pathSegments;
    final last = segments.isNotEmpty ? segments.last.trim() : '';
    if (last.isNotEmpty) return last;
    final (prefix, extension) = _assetNaming;
    return '$prefix'
        '${DateTime.now().millisecondsSinceEpoch}'
        '$extension';
  }

  /// Best-effort SHA-256 verification against a sibling
  /// `<installer-filename>.sha256` release asset, if the release publishes
  /// one.
  ///
  /// This is a clean extension point, not a hard requirement yet: until
  /// installer/build_release.ps1 produces a checksum file alongside the
  /// installer, `$downloadUrl.sha256` 404s for every release and this
  /// silently returns without altering [downloadUpdate]'s behavior at all.
  /// The moment the release pipeline starts publishing that sibling asset
  /// (a plain-text file containing the 64-character hex SHA-256 digest,
  /// with or without a trailing filename in the usual `sha256sum` output
  /// style), verification switches on automatically: the downloaded
  /// installer is hashed and compared, and a mismatch deletes the file and
  /// throws so a corrupted or tampered installer is never handed to
  /// [launchUpdaterAndExit].
  static Future<void> _verifyChecksumIfAvailable(
    http.Client client,
    String downloadUrl,
    File installerFile,
  ) async {
    String expectedHex;
    try {
      final checksumResponse = await client
          .get(Uri.parse('$downloadUrl.sha256'))
          .timeout(const Duration(seconds: 10));

      if (checksumResponse.statusCode != 200) return;

      final match =
          RegExp(r'[0-9a-fA-F]{64}').firstMatch(checksumResponse.body);
      if (match == null) return;

      expectedHex = match.group(0)!.toLowerCase();
    } catch (_) {
      // No checksum asset published (or transiently unreachable) — treated
      // as "checksum support not implemented for this release", not as an
      // error. Existing releases without a .sha256 asset must keep working
      // exactly as they do today.
      return;
    }

    // Hashed in chunks straight off disk. readAsBytes() would pull the
    // whole 66 MB APK into one allocation and hash it in a single
    // synchronous pass — unremarkable on Windows, but on a low-end phone
    // it is either an out-of-memory kill or a multi-second freeze of the
    // UI thread, arriving exactly at 100%. Both look to the user like the
    // download completing and then nothing happening at all.
    final digest = await sha256.bind(installerFile.openRead()).first;
    final actualHex = digest.toString();

    if (actualHex != expectedHex) {
      await _deleteQuietly(installerFile);
      throw Exception(
        'Checksum verification failed — the downloaded installer does not '
        'match the published SHA-256 digest. Update aborted.',
      );
    }
  }

  /// Removes a rejected download. Best-effort: the exception the caller is
  /// about to throw is what carries the failure, and a file left behind in
  /// the cache directory is harmless — the next attempt overwrites it.
  static Future<void> _deleteQuietly(File file) async {
    try {
      await file.delete();
    } catch (_) {
      // Intentionally ignored.
    }
  }

  /// Launches the downloaded installer silently and exits the app.
  ///
  /// [installerPath] is the local path returned by [downloadUpdate].
  ///
  /// `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-` run the installer
  /// fully unattended — no wizard pages, no message boxes, no forced
  /// reboot, no "This will install..." confirmation prompt. Inno Setup's
  /// native CloseApplications (see installer/growmont_installer.iss)
  /// closes the currently-running growmont_crm.exe before copying files
  /// over it, and its [Run] section's `skipifnotsilent` entry relaunches
  /// growmont_crm.exe once the silent install finishes — so nothing
  /// further is required here once the installer process has been
  /// started.
  ///
  /// [newVersion] is intentionally unused here: the installer embeds the
  /// real version at build time (VersionInfoVersion in
  /// growmont_installer.iss, sourced from pubspec.yaml — see RELEASE.md),
  /// so the relaunched growmont_crm.exe reports the new version directly
  /// via `PackageInfo.fromPlatform()` in [getCurrentVersion] with no file
  /// to write. The parameter is kept only so this method's signature
  /// keeps matching the call in UpdateNotifier.downloadAndInstall().
  ///
  /// Returns `null` on success — on Windows the process calls `exit(0)`, so
  /// callers never actually observe that return value. Returns a non-null
  /// error string that the UI can display on any failure.
  ///
  /// On Android this delegates to [_installApkAndroid], which cannot be
  /// silent and does not exit the app — see that method for why.
  static Future<String?> launchUpdaterAndExit(
    String installerPath,
    String newVersion,
  ) async {
    try {
      if (Platform.isAndroid) {
        return _installApkAndroid(installerPath);
      }

      if (!Platform.isWindows) {
        return 'Auto-update is only supported on Windows and Android.';
      }

      final installerFile = File(installerPath);
      if (!installerFile.existsSync() || installerFile.lengthSync() == 0) {
        return 'Update installer is missing or empty ($installerPath).';
      }

      await Process.start(
        installerPath,
        const ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-'],
        workingDirectory: installerFile.parent.path,
        mode: ProcessStartMode.detached,
        runInShell: false,
      );

      await Future<void>.delayed(const Duration(milliseconds: 1500));
      exit(0);
    } catch (e) {
      return 'Failed to launch installer: $e';
    }
  }

  /// Hands the downloaded APK to the Android package installer.
  ///
  /// This deliberately does **not** mirror the Windows path:
  ///
  /// - It is not silent. Android gives a sideloaded app no way to install
  ///   an APK without the user confirming on a system-drawn screen. Any
  ///   API that could do so would be a complete device-compromise vector,
  ///   so none exists outside of device-owner/system-app contexts.
  /// - It does not call `exit(0)`. The installer runs in its own process;
  ///   killing ourselves here would tear the app out from under the
  ///   confirmation dialog the user still has to accept. Android stops our
  ///   process itself when it replaces the APK, and the user reopens from
  ///   the launcher.
  ///
  /// The common first-run failure is the per-app "install unknown apps"
  /// setting being off, which is the default. Rather than firing an intent
  /// that silently does nothing, that case is detected up front and the
  /// user is sent to the exact settings page.
  static Future<String?> _installApkAndroid(String apkPath) async {
    final apkFile = File(apkPath);
    if (!apkFile.existsSync() || apkFile.lengthSync() == 0) {
      return 'Downloaded update is missing or empty ($apkPath).';
    }

    try {
      final canInstall =
          await _installerChannel.invokeMethod<bool>('canInstallPackages');

      if (canInstall != true) {
        final opened = await _installerChannel
            .invokeMethod<bool>('openInstallSettings');
        return opened == true
            ? 'Allow "Install unknown apps" for Growmont CRM on the screen '
                'that just opened, then tap Update again.'
            : 'Android is blocking app installs from Growmont CRM. Enable '
                '"Install unknown apps" for it in Settings > Apps, then tap '
                'Update again.';
      }

      await _installerChannel.invokeMethod<bool>(
        'installApk',
        {'path': apkPath},
      );
      return null;
    } on PlatformException catch (e) {
      return 'Failed to start the installer: ${e.message ?? e.code}';
    } catch (e) {
      return 'Failed to start the installer: $e';
    }
  }

  /// Channel implemented by MainActivity.kt. Android-only; every call site
  /// is already behind a `Platform.isAndroid` check.
  static const MethodChannel _installerChannel =
      MethodChannel('com.growmont.growmont_crm/installer');

  static bool _isNewer(String candidate, String current) {
    final c = _parse(candidate);
    final cur = _parse(current);
    for (var i = 0; i < 3; i++) {
      if (c[i] > cur[i]) return true;
      if (c[i] < cur[i]) return false;
    }
    return false;
  }

  static List<int> _parse(String version) {
    final parts = version.split('.');
    return List<int>.generate(
      3,
      (i) => i < parts.length ? int.tryParse(parts[i]) ?? 0 : 0,
    );
  }
}

/// Minimal internal holder for the parts of a GitHub release that
/// [UpdateService] cares about. Not exported — [UpdateInfo] remains the
/// public shape callers work with.
class _LatestRelease {
  const _LatestRelease({
    required this.version,
    required this.downloadUrl,
    required this.message,
  });

  final String version;
  final String downloadUrl;
  final String message;
}
