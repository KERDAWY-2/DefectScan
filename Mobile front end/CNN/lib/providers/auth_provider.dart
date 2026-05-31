import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

class AuthProvider extends ChangeNotifier {
  String? _token;
  Map<String, dynamic>? _user;
  bool _initialized = false;

  String? get token => _token;
  Map<String, dynamic>? get user => _user;
  bool get isLoggedIn => _token != null;
  bool get isInitialized => _initialized;

  // Load token from storage on app start. Survives MainActivity recreation
  // (Android can kill the process while ImagePicker runs and re-launch later).
  Future<void> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');
    if (_token != null) {
      try {
        _user = await ApiService.getMe(_token!);
      } catch (_) {
        // Stored token is unusable (server down, expired, etc.) — clear it
        // so the gate falls back to login instead of looping forever.
        _token = null;
        await prefs.remove('token');
      }
    }
    _initialized = true;
    notifyListeners();
  }

  // Login
  Future<bool> login(String username, String password) async {
    final data = await ApiService.login(username, password);
    if (data.containsKey('access_token')) {
      _token = data['access_token'];
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', _token!);
      _user = await ApiService.getMe(_token!);
      notifyListeners();
      return true;
    }
    return false;
  }

  // Register
  Future<bool> register(String username, String email, String password, String secondName, String nationalId, String mobile, String address) async {
    final data = await ApiService.register(username, email, password, secondName, nationalId, mobile, address);
    return data.containsKey('id');
  }

  // Logout
  Future<void> logout() async {
    _token = null;
    _user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    notifyListeners();
  }
}
