import 'dart:async';
import 'dart:io' show Platform;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../models/user.dart';
import '../../core/providers.dart';
import '../../core/storage/token_storage.dart';
import 'google_oauth_desktop.dart';

class AuthState {
  const AuthState({this.user, this.accessToken, this.isLoading = true});

  final AppUser? user;
  final String? accessToken;
  final bool isLoading;

  bool get isAuthenticated => user != null;

  AuthState copyWith({
    AppUser? user,
    String? accessToken,
    bool? isLoading,
    bool clearUser = false,
  }) {
    return AuthState(
      user: clearUser ? null : (user ?? this.user),
      accessToken: clearUser ? null : (accessToken ?? this.accessToken),
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class AuthNotifier extends Notifier<AuthState> {
  late TokenStorage _storage;
  StreamSubscription<User?>? _authSubscription;

  @override
  AuthState build() {
    _storage = ref.read(tokenStorageProvider);

    _authSubscription?.cancel();
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen(
      _onAuthStateChanged,
    );

    ref.onDispose(() {
      _authSubscription?.cancel();
    });

    return const AuthState(isLoading: true);
  }

  bool _isBypassed = false;

  Future<void> _onAuthStateChanged(User? firebaseUser) async {
    if (_isBypassed) return;

    if (firebaseUser == null) {
      final cachedUser = await _storage.getUser();
      final cachedToken = await _storage.getAccessToken();
      if (cachedToken == 'dev-bypass-token' && cachedUser != null) {
        _isBypassed = true;
        state = AuthState(
          user: cachedUser,
          accessToken: cachedToken,
          isLoading: false,
        );
        return;
      }
      await _storage.clear();
      state = const AuthState(isLoading: false);
      return;
    }

    try {
      final tokenResult = await firebaseUser.getIdTokenResult();
      final roleClaim = (tokenResult.claims?['role'] as String?)?.toUpperCase();

      // The employee doc's id doesn't always match the Firebase Auth uid
      // (e.g. a Google sign-in only matched by email) — resolve the actual
      // doc so downstream lookups (sales, interactions, ...) use the right
      // employee id instead of a uid that has no matching document.
      final doc = await _findEmployeeDoc(firebaseUser);

      final docData = doc?.data() ?? {};

      // Belt-and-suspenders status gate: the Cloud Functions side already
      // disables the Firebase Auth account for RESTRICTED/REJECTED users
      // (which normally stops sign-in outright), but this also runs on
      // every app-resume/token-refresh, where a cached session or a
      // just-expired grace period may not have propagated to Auth yet.
      final statusStr =
          (docData['status'] as String?)?.toUpperCase() ?? 'ACTIVE';
      if (statusStr == 'RESTRICTED' || statusStr == 'REJECTED') {
        await FirebaseAuth.instance.signOut();
        await _storage.clear();
        state = const AuthState(isLoading: false);
        return;
      }
      if (statusStr == 'PENDING') {
        final expiresAt = (docData['access_expires_at'] as Timestamp?)
            ?.toDate();
        if (expiresAt != null && DateTime.now().isAfter(expiresAt)) {
          await FirebaseAuth.instance.signOut();
          await _storage.clear();
          state = const AuthState(isLoading: false);
          return;
        }
      }

      final roleStr = roleClaim ?? docData['role'] as String? ?? 'EMPLOYEE';
      // Prefer the signed-in account's own name/photo (e.g. from Google)
      // over the employee record, which usually has neither set.
      final name =
          firebaseUser.displayName ??
          docData['name'] as String? ??
          firebaseUser.email?.split('@').first ??
          'User';
      final avatar = firebaseUser.photoURL ?? docData['avatar_url'] as String?;

      final appUser = AppUser(
        id: doc?.id ?? firebaseUser.uid,
        name: name,
        email: firebaseUser.email ?? '',
        avatar: avatar,
        role: roleStr == 'ADMIN' ? UserRole.admin : UserRole.employee,
      );

      await _storage.saveSession(
        accessToken: tokenResult.token ?? '',
        refreshToken: '',
        user: appUser,
      );

      state = AuthState(
        user: appUser,
        accessToken: tokenResult.token,
        isLoading: false,
      );
    } catch (e) {
      // Fallback in case of network issue on startup
      final cachedUser = await _storage.getUser();
      if (cachedUser != null) {
        state = AuthState(user: cachedUser, accessToken: '', isLoading: false);
      } else {
        state = const AuthState(isLoading: false);
      }
    }
  }

  Future<void> bypassLogin({UserRole role = UserRole.admin}) async {
    _isBypassed = true;
    state = state.copyWith(isLoading: true);

    try {
      await FirebaseAuth.instance.signInAnonymously();
    } catch (_) {}

    final appUser = AppUser(
      id: role == UserRole.admin ? 'dev-admin' : 'dev-employee',
      name: role == UserRole.admin ? 'Dev Admin' : 'Dev Employee',
      email: role == UserRole.admin
          ? 'admin@growmont.com'
          : 'employee@growmont.com',
      avatar: null,
      role: role,
    );

    try {
      await _storage.saveSession(
        accessToken: 'dev-bypass-token',
        refreshToken: '',
        user: appUser,
      );
    } catch (_) {}

    state = AuthState(
      user: appUser,
      accessToken: 'dev-bypass-token',
      isLoading: false,
    );
  }

  Future<String?> login(String usernameOrEmail, String password) async {
    _isBypassed = false;
    state = state.copyWith(isLoading: true);
    try {
      String email = usernameOrEmail.trim();
      if (!email.contains('@')) {
        email = '$email@growmont.com';
      }

      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (cred.user != null) {
        await _onAuthStateChanged(cred.user);
      }
      return null;
    } on FirebaseAuthException catch (e) {
      state = state.copyWith(isLoading: false);
      switch (e.code) {
        case 'user-not-found':
          return 'No employee account found with this email.';
        case 'wrong-password':
        case 'invalid-credential':
          return 'Incorrect password. Please verify your credentials.';
        case 'user-disabled':
          return 'This employee account has been disabled.';
        case 'invalid-email':
          return 'The email address format is invalid.';
        default:
          return e.message ?? 'Authentication failed.';
      }
    } catch (e) {
      state = state.copyWith(isLoading: false);
      return e.toString();
    }
  }

  /// Signs in with Google via Firebase Auth. A Google account that matches
  /// an existing `employees` document (by uid or email) signs in per its
  /// current status; a brand-new account is auto-provisioned as PENDING
  /// with a 3-day grace period of full employee-level access (see
  /// `provisionPendingEmployee` in functions/index.js). Returns null on
  /// success (or user cancellation), or an error message to show on the
  /// login screen.
  Future<String?> signInWithGoogle() async {
    _isBypassed = false;
    state = state.copyWith(isLoading: true);

    final useDesktopFlow = !kIsWeb && (Platform.isWindows || Platform.isLinux);
    GoogleSignIn? googleSignIn;

    try {
      String? idToken;
      String? accessToken;

      if (useDesktopFlow) {
        final result = await DesktopGoogleSignIn.instance.signIn();
        if (result == null) {
          // User cancelled in the browser — not an error.
          state = state.copyWith(isLoading: false);
          return null;
        }
        idToken = result.idToken;
        accessToken = result.accessToken;
      } else {
        googleSignIn = GoogleSignIn(scopes: const ['email', 'profile']);
        final googleUser = await googleSignIn.signIn();
        if (googleUser == null) {
          // User closed the account picker — not an error.
          state = state.copyWith(isLoading: false);
          return null;
        }
        final googleAuth = await googleUser.authentication;
        idToken = googleAuth.idToken;
        accessToken = googleAuth.accessToken;
      }

      final credential = GoogleAuthProvider.credential(
        accessToken: accessToken,
        idToken: idToken,
      );

      final cred = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );
      final firebaseUser = cred.user;
      if (firebaseUser == null) {
        state = state.copyWith(isLoading: false);
        return 'Google sign-in failed. Please try again.';
      }

      final doc = await _findEmployeeDoc(firebaseUser);

      if (doc == null) {
        // Brand-new Google account — auto-provision as PENDING (3-day grace
        // period) instead of rejecting outright. Runs server-side via a
        // Cloud Function callable so custom claims and the Firestore doc
        // are set atomically and the client never needs write access to
        // employees/*.
        try {
          await ref.read(firestoreServiceProvider).provisionPendingEmployee();
        } catch (e) {
          await FirebaseAuth.instance.signOut();
          await googleSignIn?.signOut();
          state = state.copyWith(isLoading: false);
          return 'Could not set up your account. Please try again or '
              'contact your administrator.';
        }
        await _onAuthStateChanged(firebaseUser);
        return null;
      }

      final data = doc.data() ?? {};
      final status = (data['status'] as String?)?.toUpperCase() ?? 'ACTIVE';

      if (status == 'RESTRICTED' || status == 'REJECTED') {
        await FirebaseAuth.instance.signOut();
        await googleSignIn?.signOut();
        state = state.copyWith(isLoading: false);
        return 'Your account is waiting for admin approval. Contact your '
            'administrator.';
      }

      if (status == 'PENDING') {
        final expiresAt = (data['access_expires_at'] as Timestamp?)
            ?.toDate();
        if (expiresAt != null && DateTime.now().isAfter(expiresAt)) {
          // Grace window lapsed but the scheduled sweep hasn't caught it
          // yet — block here rather than letting a stale PENDING doc grant
          // access past the 3 days.
          await FirebaseAuth.instance.signOut();
          await googleSignIn?.signOut();
          state = state.copyWith(isLoading: false);
          return 'Your access request has expired. Contact your '
              'administrator.';
        }
        // Still within the 3-day window — full employee access.
      }

      await _onAuthStateChanged(firebaseUser);
      return null;
    } on FirebaseAuthException catch (e) {
      state = state.copyWith(isLoading: false);
      switch (e.code) {
        case 'account-exists-with-different-credential':
          return 'An account already exists for this email with a '
              'different sign-in method.';
        case 'invalid-credential':
          return 'The Google credential is invalid or has expired. '
              'Please try again.';
        case 'user-disabled':
          return 'This employee account has been disabled.';
        case 'operation-not-allowed':
          return 'Google sign-in is not enabled for this project yet.';
        default:
          return e.message ?? 'Google sign-in failed.';
      }
    } on DesktopSignInException catch (e) {
      state = state.copyWith(isLoading: false);
      return e.message;
    } catch (e) {
      state = state.copyWith(isLoading: false);
      return 'Google sign-in failed. Please try again.';
    }
  }

  /// Resolves the `employees` document for [firebaseUser], matching first
  /// by document id (uid) and falling back to an email match — a Google
  /// sign-in's uid won't match a pre-existing employee doc created under a
  /// different id, so callers must use the returned doc's id, not the uid.
  Future<DocumentSnapshot<Map<String, dynamic>>?> _findEmployeeDoc(
    User firebaseUser,
  ) async {
    final byUid = await FirebaseFirestore.instance
        .collection('employees')
        .doc(firebaseUser.uid)
        .get();
    if (byUid.exists) return byUid;

    final email = firebaseUser.email;
    if (email == null) return null;

    final byEmail = await FirebaseFirestore.instance
        .collection('employees')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();
    return byEmail.docs.isNotEmpty ? byEmail.docs.first : null;
  }

  Future<void> logout() async {
    state = const AuthState(isLoading: true);
    _isBypassed = false;
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    try {
      await _storage.clear();
    } catch (_) {}
    state = const AuthState(isLoading: false);
  }

  Future<String?> sendPasswordReset(String email) async {
    try {
      String cleanEmail = email.trim();
      if (!cleanEmail.contains('@')) {
        cleanEmail = '$cleanEmail@growmont.com';
      }
      await FirebaseAuth.instance.sendPasswordResetEmail(email: cleanEmail);
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'Failed to send password reset email.';
    } catch (e) {
      return e.toString();
    }
  }

  Future<void> handleUnauthorized() async {
    await logout();
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
