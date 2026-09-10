// lib/core/updater/version_constants.dart

/// GitHub repository that hosts Growmont CRM releases.
///
/// This is the ONLY place the owner/repo pair is declared. Anything that
/// needs to talk to GitHub about releases (update checks, download URLs,
/// release page links) should derive from these two constants instead of
/// hardcoding the path again elsewhere.
///
/// TODO(release-repo): replace with the real public release repo once it
/// exists (see LOCAL_FIRST_AND_UPDATER_PLAN.md Phase 7.1 / Phase 10). Until
/// then, checkForUpdate() gracefully reports "no update information
/// available" against this placeholder rather than erroring.
const String kGitHubRepoOwner = 'REPLACE_ME_OWNER';
const String kGitHubRepoName = 'REPLACE_ME_REPO';

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
