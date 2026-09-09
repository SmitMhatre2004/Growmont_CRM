import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// Thrown for configuration or flow errors during desktop Google sign-in.
/// [message] is safe to show directly to the user.
class DesktopSignInException implements Exception {
  DesktopSignInException(this.message);
  final String message;

  @override
  String toString() => message;
}

class DesktopGoogleAuthResult {
  const DesktopGoogleAuthResult({required this.idToken, this.accessToken});
  final String idToken;
  final String? accessToken;
}

/// Google Sign-In for platforms the `google_sign_in` plugin has no native
/// implementation for (Windows, Linux): opens the system browser to
/// Google's consent screen and completes the flow via a local loopback
/// redirect + PKCE, per Google's "OAuth 2.0 for Desktop Apps" guide.
///
/// Requires a Google Cloud OAuth client of type **Desktop app** — separate
/// from the Android/iOS/Web clients already in google-services.json, since
/// only the Desktop app client type accepts a loopback redirect URI on an
/// arbitrary port without pre-registering it. Create one in the same GCP
/// project (growmontcrm) at APIs & Services > Credentials > Create
/// Credentials > OAuth client ID > Desktop app, then rebuild with:
///   --dart-define=GOOGLE_DESKTOP_CLIENT_ID=xxx.apps.googleusercontent.com
///   --dart-define=GOOGLE_DESKTOP_CLIENT_SECRET=xxx
class DesktopGoogleSignIn {
  DesktopGoogleSignIn._();
  static final DesktopGoogleSignIn instance = DesktopGoogleSignIn._();

  static const _clientId = String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_ID');
  static const _clientSecret = String.fromEnvironment(
    'GOOGLE_DESKTOP_CLIENT_SECRET',
  );

  static const _authEndpoint = 'https://accounts.google.com/o/oauth2/v2/auth';
  static const _tokenEndpoint = 'https://oauth2.googleapis.com/token';
  static const _scopes = 'openid email profile';
  static const _authTimeout = Duration(minutes: 3);

  final _random = Random.secure();

  /// Runs the full loopback flow. Returns null if the user cancels (denies
  /// consent / closes the browser tab).
  Future<DesktopGoogleAuthResult?> signIn() async {
    if (_clientId.isEmpty) {
      throw DesktopSignInException(
        'Google sign-in is not configured for desktop yet. Ask an admin to '
        'create a "Desktop app" OAuth client and rebuild with '
        '--dart-define=GOOGLE_DESKTOP_CLIENT_ID=...',
      );
    }

    final codeVerifier = _generateCodeVerifier();
    final codeChallenge = _codeChallengeFor(codeVerifier);
    final state = _generateRandomString(24);

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirectUri = 'http://127.0.0.1:${server.port}';

    try {
      final authUri = Uri.parse(_authEndpoint).replace(
        queryParameters: {
          'client_id': _clientId,
          'redirect_uri': redirectUri,
          'response_type': 'code',
          'scope': _scopes,
          'code_challenge': codeChallenge,
          'code_challenge_method': 'S256',
          'state': state,
          'prompt': 'select_account',
        },
      );

      final launched = await launchUrl(
        authUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw DesktopSignInException(
          'Could not open the browser for Google sign-in.',
        );
      }

      final code = await _awaitAuthorizationCode(server, state);
      if (code == null) return null;

      return await _exchangeCode(
        code: code,
        codeVerifier: codeVerifier,
        redirectUri: redirectUri,
      );
    } finally {
      unawaited(server.close(force: true));
    }
  }

  /// Listens for the OAuth redirect on [server], ignoring stray requests
  /// (e.g. a browser's automatic favicon fetch) until the real callback
  /// with a `code` or `error` query parameter arrives.
  Future<String?> _awaitAuthorizationCode(
    HttpServer server,
    String expectedState,
  ) async {
    final completer = Completer<String?>();
    final timer = Timer(_authTimeout, () {
      if (!completer.isCompleted) {
        completer.completeError(
          DesktopSignInException('Google sign-in timed out. Please try again.'),
        );
      }
    });

    final subscription = server.listen((request) async {
      final params = request.uri.queryParameters;
      if (!params.containsKey('code') && !params.containsKey('error')) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }

      final response = request.response
        ..headers.contentType = ContentType.html;

      if (params.containsKey('error')) {
        response.write(
          _resultPage('Sign-in cancelled', 'You can close this tab.'),
        );
        await response.close();
        if (!completer.isCompleted) completer.complete(null);
        return;
      }

      final code = params['code'];
      if (params['state'] != expectedState || code == null) {
        response.write(
          _resultPage('Sign-in failed', 'Invalid response. Close this tab and try again.'),
        );
        await response.close();
        if (!completer.isCompleted) {
          completer.completeError(
            DesktopSignInException('Google sign-in failed: invalid response.'),
          );
        }
        return;
      }

      response.write(
        _resultPage('Signed in', 'You can close this tab and return to Growmont CRM.'),
      );
      await response.close();
      if (!completer.isCompleted) completer.complete(code);
    });

    try {
      return await completer.future;
    } finally {
      timer.cancel();
      await subscription.cancel();
    }
  }

  Future<DesktopGoogleAuthResult> _exchangeCode({
    required String code,
    required String codeVerifier,
    required String redirectUri,
  }) async {
    final response = await http.post(
      Uri.parse(_tokenEndpoint),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': _clientId,
        if (_clientSecret.isNotEmpty) 'client_secret': _clientSecret,
        'code': code,
        'code_verifier': codeVerifier,
        'grant_type': 'authorization_code',
        'redirect_uri': redirectUri,
      },
    );

    if (response.statusCode != 200) {
      throw DesktopSignInException(
        'Google sign-in failed while exchanging the authorization code '
        '(${response.statusCode}).',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final idToken = body['id_token'] as String?;
    if (idToken == null) {
      throw DesktopSignInException('Google did not return an identity token.');
    }

    return DesktopGoogleAuthResult(
      idToken: idToken,
      accessToken: body['access_token'] as String?,
    );
  }

  String _resultPage(String title, String message) => '''
<!doctype html>
<html>
  <head><meta charset="utf-8"><title>$title</title></head>
  <body style="font-family: sans-serif; text-align:center; padding-top: 80px;">
    <h2>$title</h2>
    <p>$message</p>
  </body>
</html>
''';

  String _generateCodeVerifier() {
    final bytes = List<int>.generate(64, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  String _codeChallengeFor(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  String _generateRandomString(int length) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(
      length,
      (_) => chars[_random.nextInt(chars.length)],
    ).join();
  }
}
