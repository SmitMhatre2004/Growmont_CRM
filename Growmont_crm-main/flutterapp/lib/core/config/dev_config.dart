// lib/core/config/dev_config.dart
//
// Local-development switch that points the app at the Firebase Emulator
// Suite instead of the live `growmontcrm` project.
//
// ── Why this exists ──────────────────────────────────────────────────────
//
//   The CRM is deployed and in daily use. Running a development build
//   against the real project would read, and could write, live customer
//   records. Everything here is about making that impossible by accident.
//
// ── The safety rules ─────────────────────────────────────────────────────
//
//   1. OFF BY DEFAULT. [useFirebaseEmulator] is a compile-time define that
//      defaults to false, so every ordinary build — and in particular
//      anything installer/build_release.ps1 produces — behaves exactly as
//      it always has. Nothing about the production path changes.
//
//   2. NEVER IN A RELEASE BUILD. Even if someone passes the define to
//      `flutter build windows --release`, [useFirebaseEmulator] still
//      resolves false. A shipped installer therefore cannot be made to
//      point at localhost, which would otherwise look like "the app is
//      broken" to a real user.
//
//   3. SEPARATE LOCAL DATABASE. The app is local-first: SyncEngine pulls
//      Firestore documents into a SQLite file under %APPDATA%. If emulator
//      mode reused that file, test rows and real rows would end up in the
//      same database, and the next production run would sync the test rows
//      upward. [localDatabaseFileName] therefore switches to a separate
//      file, so the two data sets can never touch.
//
// ── Using it ─────────────────────────────────────────────────────────────
//
//   See DEV_TESTING.md. In short: start the emulators, seed them, then
//   `flutter run -d windows --dart-define=USE_FIREBASE_EMULATOR=true`.

import 'package:flutter/foundation.dart';

class DevConfig {
  const DevConfig._();

  /// Raw value of the compile-time define, before the release-mode guard.
  /// Exposed only so the banner can explain a define that was asked for
  /// but deliberately ignored.
  static const bool emulatorRequested = bool.fromEnvironment(
    'USE_FIREBASE_EMULATOR',
    defaultValue: false,
  );

  /// True when this build should talk to the local emulators.
  ///
  /// `!kReleaseMode` is the hard guard described in rule 2 above: debug and
  /// profile builds can opt in, a release build never can.
  static const bool useFirebaseEmulator = emulatorRequested && !kReleaseMode;

  /// True when the define was passed but suppressed because this is a
  /// release build — worth saying out loud rather than silently ignoring.
  static bool get emulatorSuppressed => emulatorRequested && kReleaseMode;

  /// Host the emulators bind to.
  ///
  /// 127.0.0.1 rather than 'localhost': the Firestore and Auth emulators
  /// listen on IPv4 only, and a resolver that tries ::1 first fails with
  /// ECONNREFUSED before falling back. An Android emulator reaches the
  /// host machine on 10.0.2.2 instead.
  static String get emulatorHost {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return '10.0.2.2';
    }
    return '127.0.0.1';
  }

  /// Ports, matching the `emulators` block in ../../firebase.json. If you
  /// change one there, change it here.
  static const int authPort = 9099;
  static const int firestorePort = 8080;
  static const int storagePort = 9199;

  /// Name of the local SQLite file. Rule 3 above: emulator runs get their
  /// own database so test data and real data never share a file.
  static String get localDatabaseFileName =>
      useFirebaseEmulator ? 'growmont-emulator.db' : 'growmont.db';
}
