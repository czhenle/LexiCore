import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// StorageService acts as the local session database for LexiCore.
class StorageService {
  final _storage = const FlutterSecureStorage();
  final String _activeUserKey = 'active_session_user';

  // === SESSION MANAGEMENT ===
  Future<String?> getActiveUser() async {
    return await _storage.read(key: _activeUserKey);
  }

  Future<void> logout() async {
    await _storage.delete(key: _activeUserKey);
  }
  
  Future<void> registerAccount(String username, String password) async {
    await _storage.write(key: '${username}_password', value: password);
  }

  Future<bool> verifyLogin(String username, String password) async {
    String? savedPassword = await _storage.read(key: '${username}_password');
    if (savedPassword != null && savedPassword == password) {
      await _storage.write(key: _activeUserKey, value: username);
      return true;
    }
    return false;
  }

  Future<Map<String, String?>> getMasterAccount() async {
    String? currentUser = await getActiveUser();
    if (currentUser == null) return {'username': null, 'password': null};
    String? pass = await _storage.read(key: '${currentUser}_password');
    return {'username': currentUser, 'password': pass};
  }

  Future<void> updateMasterPassword(String newPassword) async {
    String? currentUser = await getActiveUser();
    if (currentUser != null) {
      await _storage.write(key: '${currentUser}_password', value: newPassword);
    }
  }

  // === PROFILE MEDIA MANAGEMENT ===
  Future<void> saveProfileImagePath(String path) async {
    String? currentUser = await getActiveUser();
    await _storage.write(key: '${currentUser}_image', value: path);
  }

  Future<String?> getProfileImagePath() async {
    String? currentUser = await getActiveUser();
    return await _storage.read(key: '${currentUser}_image');
  }

  // === ONBOARDING & PROFILE DATA ===
  Future<void> saveStudentProfile(String age, int standard, String studyTime) async {
    String? currentUser = await getActiveUser();
    if (currentUser != null) {
      await _storage.write(key: '${currentUser}_age', value: age);
      await _storage.write(key: '${currentUser}_standard', value: standard.toString());
      await _storage.write(key: '${currentUser}_studyTime', value: studyTime);
    }
  }

  Future<Map<String, dynamic>> getStudentProfile() async {
    String? currentUser = await getActiveUser();
    if (currentUser == null) return {};

    String? age = await _storage.read(key: '${currentUser}_age');
    String? standardStr = await _storage.read(key: '${currentUser}_standard');
    String? studyTime = await _storage.read(key: '${currentUser}_studyTime');

    return {
      'age': age,
      'standard': standardStr != null ? int.tryParse(standardStr) : 1,
      'studyTime': studyTime,
    };
  }
}