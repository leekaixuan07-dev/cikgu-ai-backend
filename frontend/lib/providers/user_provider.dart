import 'package:flutter/material.dart';

class UserProvider extends ChangeNotifier {
  // Backend URL (10.0.2.2 for Android, localhost for Web/iOS)
  // Since we are targeting Web specifically as per request:
  final String _backendUrl = "http://127.0.0.1:8000";
  
  String? _uid;
  String? _email;
  String? _name;
  String _currentMode = "Standard"; // Standard | Remedial

  // Getters
  String get backendUrl => _backendUrl;
  String? get uid => _uid;
  String? get email => _email;
  String? get name => _name;
  String get currentMode => _currentMode;
  bool get isLoggedIn => _uid != null;

  // Setters
  void setUser(String uid, String email, String? name) {
    _uid = uid;
    _email = email;
    _name = name;
    notifyListeners();
  }

  void setMode(String mode) {
    if (_currentMode != mode) {
      _currentMode = mode;
      notifyListeners();
    }
  }

  void clearUser() {
    _uid = null;
    _email = null;
    _name = null;
    _currentMode = "Standard";
    notifyListeners();
  }
}
