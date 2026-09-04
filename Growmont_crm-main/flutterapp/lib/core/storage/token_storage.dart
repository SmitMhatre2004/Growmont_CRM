import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/user.dart';

class TokenStorage {
  TokenStorage(this._secureStorage);

  final FlutterSecureStorage _secureStorage;

  static const _accessKey = 'accessToken';
  static const _refreshKey = 'refreshToken';
  static const _userKey = 'user';

  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
    required AppUser user,
  }) async {
    await _secureStorage.write(key: _accessKey, value: accessToken);
    await _secureStorage.write(key: _refreshKey, value: refreshToken);
    await _secureStorage.write(key: _userKey, value: jsonEncode(user.toJson()));
  }

  Future<String?> getAccessToken() => _secureStorage.read(key: _accessKey);

  Future<String?> getRefreshToken() => _secureStorage.read(key: _refreshKey);

  Future<AppUser?> getUser() async {
    final raw = await _secureStorage.read(key: _userKey);
    if (raw == null) return null;
    return AppUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> clear() async {
    await _secureStorage.delete(key: _accessKey);
    await _secureStorage.delete(key: _refreshKey);
    await _secureStorage.delete(key: _userKey);
  }

  Future<String?> getStickyNotes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('stickyNotes');
  }

  Future<void> saveStickyNotes(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('stickyNotes', value);
  }
}
