import 'dart:io' show Platform;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:shared_preferences/shared_preferences.dart';

/// Chooses how privileged employee operations reach the backend.
///
/// The preferred path is the Cloud Functions callables in `functions/index.js`,
/// which run under the Admin SDK and can set custom claims. When those aren't
/// reachable the same operations run directly from the signed-in admin's
/// client instead (see `FirestoreService._createEmployeeDirect`), which works
/// on the Spark plan but cannot set claims — hence the Firestore rules accept
/// either a claim or the employee document as proof of status.
///
/// Detection is automatic and sticky in one direction only:
///
///  * A callable that succeeds proves Functions are deployed. That result is
///    persisted, and from then on this device always calls them — no probe,
///    no wasted round-trip. A later transient failure never demotes it back
///    to the direct path, so a network blip can't silently downgrade to the
///    weaker route.
///  * A callable that reports "no such function" marks Functions absent for
///    this session only. The next app launch probes again, so deploying
///    Functions switches the app over on its own with no rebuild and no
///    config to flip.
///
/// On Windows and Linux the `cloud_functions` plugin has no implementation at
/// all, so a callable throws [MissingPluginException] before reaching the
/// network. Probing there is pure latency, so it's skipped outright.
class BackendCapability {
  BackendCapability._();

  static final BackendCapability instance = BackendCapability._();

  static const _prefsKey = 'cloud_functions_available';

  bool? _knownPresent;
  bool _absentThisSession = false;

  /// Platforms with a `cloud_functions` implementation. Windows and Linux
  /// have none — see the class doc.
  bool get platformSupportsCallables {
    if (kIsWeb) return true;
    return !(Platform.isWindows || Platform.isLinux);
  }

  /// Whether the next privileged operation should try a callable.
  Future<bool> shouldUseCallables() async {
    if (!platformSupportsCallables) return false;
    if (_knownPresent == true) return true;
    if (_absentThisSession) return false;

    if (_knownPresent == null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        _knownPresent = prefs.getBool(_prefsKey) ?? false;
      } catch (_) {
        _knownPresent = false;
      }
      if (_knownPresent == true) return true;
    }

    // Never proven either way on this device — worth one probe.
    return true;
  }

  /// Records that a callable answered, so this device stops probing.
  Future<void> markPresent() async {
    if (_knownPresent == true) return;
    _knownPresent = true;
    _absentThisSession = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, true);
    } catch (_) {
      // An unwritable prefs store only costs one extra probe next launch.
    }
  }

  /// Records that Functions aren't deployed, for this session only.
  void markAbsent() {
    _absentThisSession = true;
  }

  /// Whether [error] means "this function isn't deployed" as opposed to a
  /// genuine failure inside a function that does exist. Only the former may
  /// trigger the direct path — anything else must surface to the caller so a
  /// real server-side error is never mistaken for a missing deployment.
  static bool indicatesAbsent(Object error) {
    if (error is MissingPluginException) return true;
    if (error is UnimplementedError) return true;
    if (error is FirebaseFunctionsException) {
      return error.code == 'not-found' || error.code == 'unimplemented';
    }
    return false;
  }
}

/// An employee-management failure with a message already fit to show a user.
class BackendException implements Exception {
  const BackendException(this.message);

  final String message;

  @override
  String toString() => message;
}
