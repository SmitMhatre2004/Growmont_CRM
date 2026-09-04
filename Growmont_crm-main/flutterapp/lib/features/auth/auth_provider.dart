import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/user.dart';
import '../../core/api/api_service.dart';
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

  bool get isAuthenticated => user != null && accessToken != null;

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
  late ApiService _api;

  @override
  AuthState build() {
    _storage = ref.read(tokenStorageProvider);
    _api = ref.read(apiServiceProvider);
    _restoreSession();
    return const AuthState(isLoading: true);
  }

  Future<void> _restoreSession() async {
    try {
      final token = await _storage.getAccessToken();
      final user = await _storage.getUser();
      if (token != null && user != null) {
        state = AuthState(user: user, accessToken: token, isLoading: false);
      } else {
        state = const AuthState(isLoading: false);
      }
    } catch (_) {
      state = const AuthState(isLoading: false);
    }
  }

  Future<String?> login(String username, String password) async {
    try {
      final data = await _api.login(username, password);
      final user = AppUser.fromJson(data['user'] as Map<String, dynamic>);
      final access = data['access'] as String;
      final refresh = data['refresh'] as String;

      await _storage.saveSession(
        accessToken: access,
        refreshToken: refresh,
        user: user,
      );

      state = AuthState(user: user, accessToken: access, isLoading: false);
      return null;
    } on DioException catch (e) {
      final detail = e.response?.data;
      if (detail is Map && detail['detail'] != null) {
        return detail['detail'].toString();
      }
      if (detail is Map && detail['error'] != null) {
        return detail['error'].toString();
      }
      return e.message ?? 'Login failed';
    } catch (e) {
      return e.toString();
    }
  }

  Future<void> logout() async {
    final refresh = await _storage.getRefreshToken();
    final access = state.accessToken;
    if (refresh != null && access != null) {
      await _api.logout(refresh, access);
    }
    await _storage.clear();
    state = const AuthState(isLoading: false);
  }

  Future<void> handleUnauthorized() async {
    await _storage.clear();
    state = const AuthState(isLoading: false);
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
