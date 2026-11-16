/// The only email domain permitted to sign in or be provisioned. Enforced
/// client-side in [AuthNotifier.login], in the employee create/import paths,
/// and server-side in functions/index.js.
const kAllowedEmailDomain = '@growmont.com';

/// Specific external addresses allowed to sign in despite not being on
/// [kAllowedEmailDomain] — e.g. the developer/vendor's own test account.
/// Each one still goes through the exact same approval flow as any other
/// account (self-provisions as PENDING, needs an admin to set it ACTIVE):
/// this only widens who is allowed to even attempt that, not who already
/// has access. Mirrored server-side as ADDITIONAL_ALLOWED_EMAILS in
/// functions/index.js — keep both lists in sync.
const kAdditionalAllowedEmails = {'info@svayatta.in'};

/// Region the Cloud Functions in functions/index.js are deployed to (set by
/// its setGlobalOptions). Must match, or every callable answers 404.
const kFunctionsRegion = 'asia-south1';

/// Firebase Auth's minimum password length, enforced again server-side.
const kMinPasswordLength = 6;

class AppConfig {
  static const baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  /// Link encoded in the sidebar's QR code, and opened when that card is
  /// clicked. Point it at the mobile app's download page (Play Store listing
  /// or the hosted APK); override per build with
  /// `--dart-define=APP_DOWNLOAD_URL=...` so staging can hand out a different
  /// build without a code change.
  static const appDownloadUrl = String.fromEnvironment(
    'APP_DOWNLOAD_URL',
    defaultValue: 'https://growmont.com/app',
  );

  static String mediaUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    return '$baseUrl$path';
  }
}
