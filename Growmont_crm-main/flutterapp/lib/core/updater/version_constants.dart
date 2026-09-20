// lib/core/updater/version_constants.dart

/// GitHub repository that hosts Growmont CRM releases.
///
/// This is the ONLY place the owner/repo pair is declared. Anything that
/// needs to talk to GitHub about releases (update checks, download URLs,
/// release page links) should derive from these two constants instead of
/// hardcoding the path again elsewhere.
const String kGitHubRepoOwner = 'CruciaTos';
const String kGitHubRepoName = 'GrowmontCRM_Release';

/// GitHub REST API endpoint that returns the most recently published
/// (non-draft, non-prerelease) release for the repo above.
///
/// https://docs.github.com/en/rest/releases/releases#get-the-latest-release
const String kLatestReleaseApiUrl =
    'https://api.github.com/repos/$kGitHubRepoOwner/$kGitHubRepoName/releases/latest';

/// Filename convention the installer asset attached to a GitHub release
/// must follow in order to be discovered automatically, e.g.
/// `Growmont-Setup-1.2.0.exe`. See [UpdateService] for the matching logic.
const String kInstallerAssetPrefix = 'Growmont-Setup-';
const String kInstallerAssetExtension = '.exe';

/// Android equivalents of the two constants above, e.g.
/// `growmont-1.2.0.apk`.
///
/// A distinct prefix (not just a distinct extension) keeps the two
/// platforms' assets unambiguous in a release that publishes both, and
/// means neither platform's matcher can ever select the other's artifact
/// even if an extension check were relaxed later.
///
/// The version stays in the name deliberately. A bare `growmont.apk`
/// would be shorter, but downloading two releases through a browser then
/// produces `growmont(1).apk`, and parentheses are what the package
/// installer and the scanners in front of it handle least predictably.
///
/// This must stay in step with `installer/build_android_release.ps1`,
/// which writes the file, and with whatever is actually attached to the
/// GitHub release. A mismatch is silent: the updater matches nothing and
/// reports "no update available" forever.
const String kAndroidAssetPrefix = 'growmont-';
const String kAndroidAssetExtension = '.apk';
