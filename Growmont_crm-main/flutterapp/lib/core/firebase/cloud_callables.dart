import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';

/// Calls the HTTPS callable Cloud Functions in `functions/index.js`.
///
/// Speaks the callable protocol over plain HTTPS rather than through the
/// `cloud_functions` plugin, which has no Windows or Linux implementation —
/// and the Windows app is where admins manage accounts. The protocol is small
/// and stable: POST `{"data": ...}` with the caller's Firebase ID token, get
/// back `{"result": ...}` or `{"error": {"status", "message"}}`.
/// https://firebase.google.com/docs/functions/callable-reference
///
/// Every failure surfaces as a [BackendException] whose message can be shown
/// to the user as-is: the functions word their own errors for that.
class CloudCallables {
  CloudCallables({
    http.Client? client,
    Future<String?> Function()? idToken,
    String? projectId,
  }) : _client = client ?? http.Client(),
       _idToken = idToken ?? _currentUserIdToken,
       _projectId = projectId;

  final http.Client _client;
  final Future<String?> Function() _idToken;
  final String? _projectId;

  /// Generous, because a function that has been idle starts cold.
  static const timeout = Duration(seconds: 60);

  static Future<String?> _currentUserIdToken() async =>
      FirebaseAuth.instance.currentUser?.getIdToken();

  Uri endpoint(String name) {
    final projectId = _projectId ?? Firebase.app().options.projectId;
    return Uri.https('$kFunctionsRegion-$projectId.cloudfunctions.net', name);
  }

  Future<Map<String, dynamic>> call(
    String name, [
    Map<String, dynamic> data = const {},
  ]) async {
    final token = await _idToken();
    if (token == null || token.isEmpty) {
      throw const BackendException(
        'Your session has expired. Please sign in again.',
      );
    }

    final http.Response response;
    try {
      response = await _client
          .post(
            endpoint(name),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'data': data}),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const BackendException(
        'The server took too long to respond. Please try again.',
      );
    } catch (_) {
      throw const BackendException(
        'Could not reach the server. Check your internet connection and '
        'try again.',
      );
    }

    Object? body;
    try {
      body = jsonDecode(response.body);
    } catch (_) {
      // Not JSON — e.g. Google's HTML 404 page for an undeployed function.
    }

    if (body is Map && body['error'] is Map) {
      final error = body['error'] as Map;
      throw BackendException(
        _messageFor(error['status'] as String?, error['message'] as String?),
      );
    }
    if (response.statusCode == 404) {
      throw const BackendException(
        'This action is not available on the server yet. Ask your '
        'administrator to deploy the latest Cloud Functions.',
      );
    }
    if (response.statusCode != 200 || body is! Map) {
      throw BackendException(
        'The server could not complete the request '
        '(HTTP ${response.statusCode}). Please try again.',
      );
    }

    final result = body['result'];
    return result is Map ? Map<String, dynamic>.from(result) : const {};
  }

  static String _messageFor(String? status, String? message) {
    switch (status) {
      case 'UNAUTHENTICATED':
        return 'Your session has expired. Please sign in again.';
      case 'INTERNAL':
      case 'UNKNOWN':
        // The functions log the real cause; an unexpected failure's raw
        // message is not written for users.
        return message != null && message.isNotEmpty && message != status
            ? message
            : 'Something went wrong on the server. Please try again.';
      default:
        return message != null && message.isNotEmpty
            ? message
            : 'The request was refused ($status).';
    }
  }
}

/// A backend failure with a message already fit to show a user.
class BackendException implements Exception {
  const BackendException(this.message);

  final String message;

  @override
  String toString() => message;
}
