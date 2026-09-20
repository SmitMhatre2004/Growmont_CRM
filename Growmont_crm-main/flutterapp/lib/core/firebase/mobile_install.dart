import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/auth_provider.dart';

/// Tracks whether an account has ever opened the CRM on a phone.
///
/// This exists for one reason: the desktop sidebar's "scan to install" QR is a
/// nudge, not furniture. Once the account has signed in on a phone the nudge
/// has been acted on, and the card should never come back.
///
/// The flag lives in its own `app_installs/{uid}` collection rather than as a
/// field on `employees/{uid}`, because that document is admin-write-only and
/// the entire Firestore rule model depends on nobody being able to write their
/// own employee record — see the `empData()` comment in firestore.rules.
///
/// Every entry point here fails soft. A widget test with no Firebase, a desktop
/// that is offline, a rules rejection — none of them may throw into a build, so
/// all of them degrade to "unknown", which reads as *not* installed. The card
/// failing visible is a far smaller error than the card silently never
/// appearing for anyone.
class MobileInstall {
  MobileInstall._();

  static const _collection = 'app_installs';
  static const _prefsKey = 'mobile_app_installed';

  /// Phones only. A tablet or desktop build must never mark the account as
  /// "has the mobile app" — it would suppress the QR on the very machine the
  /// QR is meant to be scanned from.
  static bool get isPhonePlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static String get _platformName {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      default:
        return 'other';
    }
  }

  /// The Firebase Auth uid — NOT `AppUser.id`, which for a Google account
  /// matched by email is the employee document's id and can differ from the
  /// uid. The security rules compare against `request.auth.uid`, so anything
  /// else here would be rejected.
  static String? _uid() {
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null; // Firebase not initialised (widget tests).
    }
  }

  static Future<bool> _readCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_prefsKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _writeCache(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, value);
    } catch (_) {
      // An unwritable prefs store only costs a card flash next launch.
    }
  }

  /// Records that this account has the app, when running on a phone.
  ///
  /// Merge-writes, so repeated launches just refresh `last_seen_at` instead of
  /// growing the document.
  static Future<void> registerIfMobile() async {
    if (!isPhonePlatform) return;

    final uid = _uid();
    if (uid == null) return;

    try {
      await FirebaseFirestore.instance.collection(_collection).doc(uid).set({
        'has_mobile': true,
        'platform': _platformName,
        'last_seen_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await _writeCache(true);
    } catch (e) {
      // Worst case the desktop keeps offering the QR — never worth an error.
      debugPrint('Mobile install not recorded: $e');
    }
  }

  /// Emits whether the account has the mobile app, starting from the cached
  /// answer so a returning user doesn't see the card flash before Firestore
  /// replies (and so an offline desktop still hides it).
  static Stream<bool> watch() async* {
    yield await _readCache();

    final uid = _uid();
    if (uid == null) return;

    final CollectionReference<Map<String, dynamic>> collection;
    try {
      collection = FirebaseFirestore.instance.collection(_collection);
    } catch (_) {
      return; // No Firebase — stay with the cached answer.
    }

    yield* collection
        .doc(uid)
        .snapshots()
        .map((snapshot) {
          final installed = snapshot.data()?['has_mobile'] == true;
          unawaited(_writeCache(installed));
          return installed;
        })
        // A rules rejection or dropped connection must not tear the stream
        // down: hold the last known answer instead.
        .handleError((Object _) {});
  }

  /// This computer's manual override of the sidebar QR, or null to follow the
  /// account signal.
  ///
  /// Stored in local prefs, never in Firestore: the whole point is that it is
  /// *this machine's* choice. A user who hides the card on a shared reception
  /// desktop shouldn't lose it on their own laptop, and someone whose phone was
  /// wiped needs a way back that an account-wide flag can't give them.
  static Future<bool?> readOverride() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_overrideKey);
    } catch (_) {
      return null;
    }
  }

  static Future<void> writeOverride(bool? value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value == null) {
        await prefs.remove(_overrideKey);
      } else {
        await prefs.setBool(_overrideKey, value);
      }
    } catch (_) {
      // Prefs being unwritable costs the choice on next launch, nothing more.
    }
  }

  static const _overrideKey = 'sidebar_qr_override';
}

/// Whether the signed-in account has opened the CRM on a phone.
///
/// Re-resolves when the signed-in user changes, so switching accounts on a
/// shared desktop doesn't inherit the previous user's answer.
final mobileAppInstalledProvider = StreamProvider<bool>((ref) {
  ref.watch(authProvider.select((s) => s.user?.id));
  return MobileInstall.watch();
});

/// Side-effecting provider that stamps `app_installs/{uid}` when this build is
/// running on a phone. Must be watched somewhere alive for the app's lifetime
/// (see `GrowmontApp.build`) — a Provider only exists while something watches
/// it. On desktop it does nothing at all.
final mobileInstallRegistrarProvider = Provider<void>((ref) {
  final uid = ref.watch(authProvider.select((s) => s.user?.id));
  if (uid != null) {
    unawaited(MobileInstall.registerIfMobile());
  }
});

/// This computer's override of the sidebar QR: true to always show it here,
/// false to always hide it here, null to follow the account signal.
///
/// Starts null while prefs load, which means a machine set to "always hide"
/// can show the card for a frame on a cold start. That's the right way round
/// to be wrong — the alternative briefly hides a card the user asked to see.
class SidebarQrOverride extends Notifier<bool?> {
  @override
  bool? build() {
    unawaited(_load());
    return null;
  }

  Future<void> _load() async {
    final stored = await MobileInstall.readOverride();
    if (stored != null) state = stored;
  }

  /// [value] of null returns this computer to following the account signal.
  Future<void> set(bool? value) async {
    state = value;
    await MobileInstall.writeOverride(value);
  }
}

final sidebarQrOverrideProvider = NotifierProvider<SidebarQrOverride, bool?>(
  SidebarQrOverride.new,
);
