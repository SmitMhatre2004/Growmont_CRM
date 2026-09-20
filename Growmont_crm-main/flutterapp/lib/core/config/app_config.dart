/// The only email domain permitted to sign in or be provisioned. Enforced
/// client-side in [AuthNotifier.login], in the employee create/import paths,
/// and server-side in functions/index.js.
const kAllowedEmailDomain = '@growmont.com';

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
