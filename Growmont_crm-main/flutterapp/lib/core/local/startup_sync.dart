// lib/core/local/startup_sync.dart

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'sync_engine.dart';

class StartupSync {
  StartupSync._();

  /// Starts SyncEngine in the background without blocking app startup.
  ///
  /// Uses Future.delayed(Duration.zero) rather than Future.microtask() so
  /// it fires on the next event-loop iteration — AFTER the first frame and
  /// after Firebase Auth's own state has settled — instead of a microtask,
  /// which runs too early (before the event loop yields) and can race
  /// against an in-flight auth/token refresh.
  static void runInBackground(FirebaseFirestore fs, String? uid) {
    Future.delayed(Duration.zero, () async {
      if (uid == null) {
        debugPrint('StartupSync: not signed in — skipping');
        return;
      }
      try {
        await SyncEngine.instance.start(fs, uid);
        debugPrint('StartupSync (background): started for $uid');
      } catch (e) {
        debugPrint('StartupSync (background) error: $e');
      }
    });
  }
}
