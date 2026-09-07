import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/user.dart';
import '../../core/providers.dart';
import '../../core/storage/token_storage.dart';

class AuthState {
  const AuthState({
    this.user,
    this.accessToken,
    this.isLoading = true,
  });

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
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen(_onAuthStateChanged);

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
        state = AuthState(user: cachedUser, accessToken: cachedToken, isLoading: false);
        return;
      }
      await _storage.clear();
      state = const AuthState(isLoading: false);
      return;
    }

    try {
      final tokenResult = await firebaseUser.getIdTokenResult();
      final roleClaim = (tokenResult.claims?['role'] as String?)?.toUpperCase();

      // Read employee document
      final doc = await FirebaseFirestore.instance
          .collection('employees')
          .doc(firebaseUser.uid)
          .get();

      final docData = doc.data() ?? {};
      final roleStr = roleClaim ?? docData['role'] as String? ?? 'EMPLOYEE';
      final name = docData['name'] as String? ?? firebaseUser.displayName ?? firebaseUser.email?.split('@').first ?? 'User';
      final avatar = docData['avatar_url'] as String? ?? firebaseUser.photoURL;

      final appUser = AppUser(
        id: firebaseUser.uid,
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
      email: role == UserRole.admin ? 'admin@growmont.com' : 'employee@growmont.com',
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

  Future<void> logout() async {
    state = const AuthState(isLoading: true);
    _isBypassed = false;
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

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
