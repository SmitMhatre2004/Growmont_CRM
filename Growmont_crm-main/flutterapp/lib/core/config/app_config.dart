/// The only email domain permitted to sign in or be provisioned. Enforced
/// client-side in [AuthNotifier.login], in the employee create/import paths,
/// and server-side in functions/index.js.
const kAllowedEmailDomain = '@growmont.com';

class AppConfig {
  static const baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  static String mediaUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    return '$baseUrl$path';
  }
}
