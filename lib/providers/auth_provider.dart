import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';
import '../models/complaint_model.dart';
import '../services/email_service.dart';
import '../services/supabase_service.dart';

class AuthProvider extends ChangeNotifier {
  Completer<void>? _storageCompleter;

  AuthProvider() {
    _initStorage();
  }

  Future<void> _initStorage() async {
    _storageCompleter = Completer<void>();
    await _loadUserDatabaseFromStorage();
    if (!_storageCompleter!.isCompleted) {
      _storageCompleter!.complete();
    }
  }

  Future<void> ensureStorageLoaded() => _ensureStorageLoaded();

  Future<void> _ensureStorageLoaded() async {
    if (_storageCompleter != null && !_storageCompleter!.isCompleted) {
      await _storageCompleter!.future;
    }
  }

  /// Authoritatively check the actual Supabase authentication session.
  /// If no valid session exists, clears local state and returns false.
  /// If a genuinely valid session exists, fetches user's role strictly from the existing user_profiles table.
  Future<bool> verifyAndRestoreSession() async {
    await _ensureStorageLoaded();
    try {
      if (!SupabaseService.isConnected) {
        _currentUser = null;
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_sessionStorageKey);
        notifyListeners();
        return false;
      }

      final client = SupabaseService.client;
      if (client == null) {
        _currentUser = null;
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_sessionStorageKey);
        notifyListeners();
        return false;
      }

      final session = client.auth.currentSession;
      if (session == null || session.isExpired) {
        await SupabaseService.logout();
        _currentUser = null;
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_sessionStorageKey);
        notifyListeners();
        return false;
      }

      // Live verification with Supabase Auth backend to confirm token is genuinely valid right now
      User? liveUser;
      try {
        final res = await client.auth.getUser().timeout(const Duration(seconds: 4));
        liveUser = res.user;
      } catch (e) {
        debugPrint('Live session verification failed or timed out: $e');
        liveUser = null;
      }

      if (liveUser == null) {
        await SupabaseService.logout();
        _currentUser = null;
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_sessionStorageKey);
        notifyListeners();
        return false;
      }

      final userId = liveUser.id;
      final cleanEmail = (liveUser.email ?? '').trim();

      // Strictly verify user's role from the existing user_profiles database table
      String? verifiedRole;
      String? verifiedName;
      String? verifiedPhone;

      try {
        final profileRes = await client
            .from('user_profiles')
            .select('role, full_name, phone')
            .eq('user_id', userId)
            .maybeSingle()
            .timeout(const Duration(seconds: 4));

        if (profileRes != null && profileRes['role'] != null) {
          final r = profileRes['role'].toString().trim().toLowerCase();
          if (r == 'reporter' || r == 'community') {
            verifiedRole = r;
            verifiedName = profileRes['full_name']?.toString().trim();
            verifiedPhone = profileRes['phone']?.toString().trim();
          }
        }

        // Secondary lookup by email in user_profiles
        if (verifiedRole == null && cleanEmail.isNotEmpty) {
          final emailRes = await client
              .from('user_profiles')
              .select('role, full_name, phone')
              .eq('email', cleanEmail.toLowerCase())
              .maybeSingle()
              .timeout(const Duration(seconds: 4));

          if (emailRes != null && emailRes['role'] != null) {
            final r = emailRes['role'].toString().trim().toLowerCase();
            if (r == 'reporter' || r == 'community') {
              verifiedRole = r;
              verifiedName ??= emailRes['full_name']?.toString().trim();
              verifiedPhone ??= emailRes['phone']?.toString().trim();
            }
          }
        }
      } catch (e) {
        debugPrint('Notice querying user_profiles during session verification: $e');
      }

      // Do not allow remembered role or arbitrary metadata to bypass database role verification
      if (verifiedRole == null || (verifiedRole != 'reporter' && verifiedRole != 'community')) {
        debugPrint('User role could not be verified from user_profiles table. Clearing session.');
        await SupabaseService.logout();
        _currentUser = null;
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_sessionStorageKey);
        notifyListeners();
        return false;
      }

      String? metaName;
      if (liveUser.userMetadata != null) {
        final candidateKeys = ['name', 'full_name', 'display_name', 'username', 'user_name'];
        for (var k in candidateKeys) {
          final v = liveUser.userMetadata![k];
          if (v != null) {
            final s = v.toString().trim();
            if (s.isNotEmpty && !s.contains('@') && s != 'Registered Voter' && s != 'Registered User') {
              metaName = s;
              break;
            }
          }
        }
      }

      final finalName = (verifiedName != null && verifiedName.isNotEmpty && !verifiedName.contains('@'))
          ? verifiedName
          : (metaName ?? _userDatabase[cleanEmail.toLowerCase()]?['name']?.toString() ?? 'Registered User');
      final finalPhone = (verifiedPhone != null && verifiedPhone.isNotEmpty)
          ? verifiedPhone
          : (liveUser.phone ?? liveUser.userMetadata?['phone'] ?? '');
      final userAvatar = liveUser.userMetadata?['avatar_url']?.toString();

      _selectedRole = verifiedRole;
      _currentUser = UserModel(
        id: userId,
        name: finalName,
        email: cleanEmail,
        phone: finalPhone,
        role: verifiedRole,
        avatarUrl: (userAvatar != null && userAvatar.trim().isNotEmpty) ? userAvatar.trim() : null,
        isVerified: true,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_sessionStorageKey, jsonEncode(_currentUser!.toJson()));
      await prefs.setString(_roleStorageKey, verifiedRole);

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error verifying session in verifyAndRestoreSession: $e');
      _currentUser = null;
      notifyListeners();
      return false;
    }
  }

  UserModel? _currentUser;
  String _selectedRole = 'reporter'; // Default role
  bool _isLoading = false;
  String? _errorMessage;

  // In-memory database of registered users (starts completely clean & empty)
  final Map<String, Map<String, String>> _userDatabase = {};

  static const String _dbStorageKey = 'roadwatch_user_db_v10';
  static const String _sessionStorageKey = 'roadwatch_active_session_v10';
  static const String _roleStorageKey = 'roadwatch_selected_role_v10';

  // Completely separate and isolated storage keys for Reporter credentials
  static const String _savedEmailReporterKey = 'roadwatch_reporter_saved_email_v12';
  static const String _savedPasswordReporterKey = 'roadwatch_reporter_saved_password_sec_v12';
  static const String _savedCredentialsMapReporterKey = 'roadwatch_reporter_saved_credentials_map_sec_v12';
  static const String _savedEmailsReporterListKey = 'roadwatch_reporter_saved_emails_list_v12';
  static const String _rememberMeReporterKey = 'roadwatch_reporter_remember_me_v12';

  // Completely separate and isolated storage keys for Community credentials
  static const String _savedEmailCommunityKey = 'roadwatch_community_saved_email_v12';
  static const String _savedPasswordCommunityKey = 'roadwatch_community_saved_password_sec_v12';
  static const String _savedCredentialsMapCommunityKey = 'roadwatch_community_saved_credentials_map_sec_v12';
  static const String _savedEmailsCommunityListKey = 'roadwatch_community_saved_emails_list_v12';
  static const String _rememberMeCommunityKey = 'roadwatch_community_remember_me_v12';

  // Legacy shared keys for cleanup
  static const String _legacyRememberMeKey = 'roadwatch_remember_me_v10';
  static const String _legacyEmailKey = 'roadwatch_saved_email_v10';
  static const String _legacyPasswordKey = 'roadwatch_saved_password_v10';
  static const String _savedCredentialsMapLegacyKey = 'roadwatch_saved_credentials_map_v10';

  static const String _removedAccountsKey = 'roadwatch_removed_accounts_v12';
  static const String _removedAccountsJsonKey = 'roadwatch_removed_accounts_json_v12';
  static const String _savedAccountsInitializedKey = 'roadwatch_saved_accounts_init_v10';

  final Map<String, String> _savedAccountsReporter = {};
  final Map<String, String> _savedAccountsCommunity = {};
  final Set<String> _savedReporterEmails = {};
  final Set<String> _savedCommunityEmails = {};
  final Set<String> _removedAccounts = {};

  static String _removedKey(String role, String email) =>
      '${role.toLowerCase().trim()}:${email.toLowerCase().trim()}';

  bool _isAccountRemoved(String role, String email) {
    return _removedAccounts.contains(_removedKey(role, email));
  }

  String? _savedEmailReporter;
  String? _savedPasswordReporter;
  String? _savedEmailCommunity;
  String? _savedPasswordCommunity;
  bool _rememberMeReporter = true;
  bool _rememberMeCommunity = true;

  static const String _keystreamSaltMaster = 'roadwatch_pujitha_auth_vault_sec_2026';

  /// Derive pseudorandom keystream for role + email bound encryption
  static List<int> _deriveKeystream(String role, String email, int length) {
    final cleanRole = role.trim().toLowerCase();
    final cleanEmail = email.trim().toLowerCase();
    final seed = '$_keystreamSaltMaster:$cleanRole:$cleanEmail';
    final seedBytes = utf8.encode(seed);

    final keystream = <int>[];
    int state = 0x811c9dc5;
    for (int b in seedBytes) {
      state = ((state ^ b) * 0x01000193) & 0xFFFFFFFF;
    }

    while (keystream.length < length) {
      state = ((state ^ 0x6c) * 0x01000193 + 0x27d4eb2f) & 0xFFFFFFFF;
      keystream.add(state & 0xFF);
      keystream.add((state >> 8) & 0xFF);
      keystream.add((state >> 16) & 0xFF);
      keystream.add((state >> 24) & 0xFF);
    }

    return keystream.sublist(0, length);
  }

  /// Encrypt a password using role-bound keystream cipher (no plaintext stored)
  static String _encryptPassword(String plainPassword, String role, String email) {
    if (plainPassword.isEmpty) return '';
    try {
      final bytes = utf8.encode(plainPassword);
      final key = _deriveKeystream(role, email, bytes.length);
      final cipherBytes = List<int>.generate(bytes.length, (i) => bytes[i] ^ key[i]);
      return 'rw_sec_v1:${base64.encode(cipherBytes)}';
    } catch (e) {
      debugPrint('Error encrypting password: $e');
      return '';
    }
  }

  /// Decrypt a password using role-bound keystream cipher
  static String _decryptPassword(String encryptedBlob, String role, String email) {
    if (encryptedBlob.isEmpty) return '';
    try {
      if (!encryptedBlob.startsWith('rw_sec_v1:')) {
        return '';
      }
      final b64 = encryptedBlob.substring('rw_sec_v1:'.length);
      final cipherBytes = base64.decode(b64);
      final key = _deriveKeystream(role, email, cipherBytes.length);
      final plainBytes = List<int>.generate(cipherBytes.length, (i) => cipherBytes[i] ^ key[i]);
      return utf8.decode(plainBytes);
    } catch (e) {
      debugPrint('Error decrypting password: $e');
      return '';
    }
  }

  static String _encodeAccountsMap(Map<String, String> map, String role) {
    final encMap = <String, String>{};
    for (var entry in map.entries) {
      if (entry.key.isNotEmpty && entry.value.isNotEmpty) {
        encMap[entry.key] = _encryptPassword(entry.value, role, entry.key);
      }
    }
    return jsonEncode(encMap);
  }

  static Map<String, String> _decodeAccountsMap(String jsonString, String role) {
    final result = <String, String>{};
    if (jsonString.isEmpty) return result;
    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is Map) {
        decoded.forEach((k, v) {
          final email = k.toString().trim();
          final val = v?.toString() ?? '';
          if (email.isNotEmpty && val.isNotEmpty) {
            final plainPwd = _decryptPassword(val, role, email);
            if (plainPwd.isNotEmpty) {
              result[email] = plainPwd;
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Error decoding accounts map: $e');
    }
    return result;
  }

  String? getSavedEmail([String? role]) {
    final targetRole = (role ?? _selectedRole).toLowerCase();
    if (targetRole == 'community') {
      return _rememberMeCommunity ? _savedEmailCommunity : null;
    } else {
      return _rememberMeReporter ? _savedEmailReporter : null;
    }
  }

  String? getSavedPassword([String? role]) {
    final targetRole = (role ?? _selectedRole).toLowerCase();
    if (targetRole == 'community') {
      return _rememberMeCommunity ? _savedPasswordCommunity : null;
    } else {
      return _rememberMeReporter ? _savedPasswordReporter : null;
    }
  }

  bool getRememberMe([String? role]) {
    final targetRole = (role ?? _selectedRole).toLowerCase();
    return targetRole == 'community' ? _rememberMeCommunity : _rememberMeReporter;
  }

  Future<void> setRememberMe(bool value, [String? role]) async {
    final targetRole = (role ?? _selectedRole).toLowerCase();
    final prefs = await SharedPreferences.getInstance();
    if (targetRole == 'community') {
      _rememberMeCommunity = value;
      await prefs.setBool(_rememberMeCommunityKey, value);
    } else {
      _rememberMeReporter = value;
      await prefs.setBool(_rememberMeReporterKey, value);
    }
    notifyListeners();
  }

  String? get savedEmail => getSavedEmail();
  String? get savedPassword => getSavedPassword();
  bool get rememberMe => getRememberMe();

  /// Get list of saved emails strictly filtered by target role
  List<String> getAvailableSavedEmails([String? role]) {
    final targetRole = (role ?? _selectedRole).toLowerCase();
    final sourceSet = targetRole == 'community' ? _savedCommunityEmails : _savedReporterEmails;
    final filtered = <String>[];

    for (var email in sourceSet) {
      final emailKey = email.trim().toLowerCase();
      if (!_isAccountRemoved(targetRole, emailKey) && email.trim().isNotEmpty) {
        if (!filtered.contains(email.trim())) {
          filtered.add(email.trim());
        }
      }
    }

    return filtered;
  }

  /// Map representation of saved accounts for UI compatibility
  Map<String, String> getAvailableSavedAccounts([String? role]) {
    final targetRole = (role ?? _selectedRole).toLowerCase();
    final emails = getAvailableSavedEmails(targetRole);
    final map = <String, String>{};
    for (var email in emails) {
      final pwd = targetRole == 'community' 
          ? (_savedAccountsCommunity[email] ?? '')
          : (_savedAccountsReporter[email] ?? '');
      map[email] = pwd;
    }
    return map;
  }

  Future<void> _loadUserDatabaseFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 1. Load User Database
      final storedJson = prefs.getString(_dbStorageKey);
      if (storedJson != null && storedJson.isNotEmpty) {
        final Map<String, dynamic> decoded = jsonDecode(storedJson);
        decoded.forEach((key, value) {
          if (value is Map) {
            final mapData = Map<String, String>.from(
              value.map((k, v) => MapEntry(k.toString(), v.toString())),
            );
            final normKey = key.toString().trim().toLowerCase();
            mapData['is_verified'] = 'true'; // Ensure loaded accounts are marked verified
            _userDatabase[normKey] = mapData;
          }
        });
      }

      // 2. Load Selected Role
      final savedRole = prefs.getString(_roleStorageKey);
      if (savedRole != null && savedRole.isNotEmpty) {
        _selectedRole = savedRole;
      }

      // 3. User session must not be assumed from local storage alone.
      // Must be validated against Supabase via verifyAndRestoreSession().
      if (_currentUser == null) {
        _currentUser = null;
      }

      // 4. Load Removed Accounts Blacklist
      _removedAccounts.clear();
      final removedList = prefs.getStringList(_removedAccountsKey);
      if (removedList != null && removedList.isNotEmpty) {
        _removedAccounts.addAll(removedList.map((e) => e.toLowerCase().trim()));
      }
      final removedJson = prefs.getString(_removedAccountsJsonKey);
      if (removedJson != null && removedJson.isNotEmpty) {
        try {
          final List<dynamic> decoded = jsonDecode(removedJson);
          _removedAccounts.addAll(decoded.map((e) => e.toString().toLowerCase().trim()));
        } catch (_) {}
      }

      // 5. Load Saved Emails Lists per role with completely distinct preferences & secure encryption
      _rememberMeReporter = prefs.getBool(_rememberMeReporterKey) ?? true;
      _rememberMeCommunity = prefs.getBool(_rememberMeCommunityKey) ?? true;

      _savedEmailReporter = prefs.getString(_savedEmailReporterKey);
      final rawPassReporter = prefs.getString(_savedPasswordReporterKey);
      if (_savedEmailReporter != null && rawPassReporter != null && rawPassReporter.isNotEmpty) {
        _savedPasswordReporter = _decryptPassword(rawPassReporter, 'reporter', _savedEmailReporter!);
      } else {
        _savedPasswordReporter = null;
      }

      _savedEmailCommunity = prefs.getString(_savedEmailCommunityKey);
      final rawPassCommunity = prefs.getString(_savedPasswordCommunityKey);
      if (_savedEmailCommunity != null && rawPassCommunity != null && rawPassCommunity.isNotEmpty) {
        _savedPasswordCommunity = _decryptPassword(rawPassCommunity, 'community', _savedEmailCommunity!);
      } else {
        _savedPasswordCommunity = null;
      }

      _savedReporterEmails.clear();
      _savedCommunityEmails.clear();
      _savedAccountsReporter.clear();
      _savedAccountsCommunity.clear();

      final repEmails = prefs.getStringList(_savedEmailsReporterListKey);
      if (repEmails != null && repEmails.isNotEmpty) {
        for (var e in repEmails) {
          final clean = e.trim();
          if (clean.isNotEmpty && !_isAccountRemoved('reporter', clean)) {
            _savedReporterEmails.add(clean);
          }
        }
      }

      final commEmails = prefs.getStringList(_savedEmailsCommunityListKey);
      if (commEmails != null && commEmails.isNotEmpty) {
        for (var e in commEmails) {
          final clean = e.trim();
          if (clean.isNotEmpty && !_isAccountRemoved('community', clean)) {
            _savedCommunityEmails.add(clean);
          }
        }
      }

      final reporterMapJson = prefs.getString(_savedCredentialsMapReporterKey);
      if (reporterMapJson != null && reporterMapJson.isNotEmpty) {
        final decodedMap = _decodeAccountsMap(reporterMapJson, 'reporter');
        decodedMap.forEach((k, v) {
          final emailKey = k.trim().toLowerCase();
          if (k.trim().isNotEmpty && !_isAccountRemoved('reporter', emailKey)) {
            _savedReporterEmails.add(k.trim());
            _savedAccountsReporter[k.trim()] = v;
          }
        });
      }

      final communityMapJson = prefs.getString(_savedCredentialsMapCommunityKey);
      if (communityMapJson != null && communityMapJson.isNotEmpty) {
        final decodedMap = _decodeAccountsMap(communityMapJson, 'community');
        decodedMap.forEach((k, v) {
          final emailKey = k.trim().toLowerCase();
          if (k.trim().isNotEmpty && !_isAccountRemoved('community', emailKey)) {
            _savedCommunityEmails.add(k.trim());
            _savedAccountsCommunity[k.trim()] = v;
          }
        });
      }

      if (_savedEmailReporter != null && _savedEmailReporter!.trim().isNotEmpty) {
        if (!_isAccountRemoved('reporter', _savedEmailReporter!.trim())) {
          _savedReporterEmails.add(_savedEmailReporter!.trim());
          if (_savedPasswordReporter != null && _savedPasswordReporter!.isNotEmpty) {
            _savedAccountsReporter[_savedEmailReporter!.trim()] = _savedPasswordReporter!;
          }
        }
      }
      if (_savedEmailCommunity != null && _savedEmailCommunity!.trim().isNotEmpty) {
        if (!_isAccountRemoved('community', _savedEmailCommunity!.trim())) {
          _savedCommunityEmails.add(_savedEmailCommunity!.trim());
          if (_savedPasswordCommunity != null && _savedPasswordCommunity!.isNotEmpty) {
            _savedAccountsCommunity[_savedEmailCommunity!.trim()] = _savedPasswordCommunity!;
          }
        }
      }

      // Clean up legacy shared keys so they never leak or cross-populate portals
      await prefs.remove(_legacyEmailKey);
      await prefs.remove(_legacyPasswordKey);
      await prefs.remove(_savedCredentialsMapLegacyKey);
      await prefs.remove(_legacyRememberMeKey);

      notifyListeners();
    } catch (e) {
      debugPrint('Error loading user database from storage: $e');
    }
  }

  /// Save or clear remembered credentials on sign in for a specific role
  Future<void> saveCredentials({
    required String email,
    required String password,
    required bool rememberMe,
    String? role,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final targetRole = (role ?? _selectedRole).toLowerCase();
      final cleanEmail = email.trim();
      final cleanPassword = password.trim();
      final emailKey = cleanEmail.toLowerCase();

      if (targetRole == 'community') {
        _rememberMeCommunity = rememberMe;
        await prefs.setBool(_rememberMeCommunityKey, rememberMe);
      } else {
        _rememberMeReporter = rememberMe;
        await prefs.setBool(_rememberMeReporterKey, rememberMe);
      }

      if (rememberMe) {
        _removedAccounts.remove(_removedKey(targetRole, emailKey));
        final removedList = _removedAccounts.toList();
        await prefs.setStringList(_removedAccountsKey, removedList);
        await prefs.setString(_removedAccountsJsonKey, jsonEncode(removedList));

        final encPassword = _encryptPassword(cleanPassword, targetRole, cleanEmail);

        if (targetRole == 'community') {
          _savedEmailCommunity = cleanEmail;
          _savedPasswordCommunity = cleanPassword;
          _savedCommunityEmails.add(cleanEmail);
          _savedAccountsCommunity[cleanEmail] = cleanPassword;

          await prefs.setString(_savedEmailCommunityKey, cleanEmail);
          await prefs.setString(_savedPasswordCommunityKey, encPassword);
          await prefs.setStringList(_savedEmailsCommunityListKey, _savedCommunityEmails.toList());
          await prefs.setString(_savedCredentialsMapCommunityKey, _encodeAccountsMap(_savedAccountsCommunity, 'community'));
        } else {
          _savedEmailReporter = cleanEmail;
          _savedPasswordReporter = cleanPassword;
          _savedReporterEmails.add(cleanEmail);
          _savedAccountsReporter[cleanEmail] = cleanPassword;

          await prefs.setString(_savedEmailReporterKey, cleanEmail);
          await prefs.setString(_savedPasswordReporterKey, encPassword);
          await prefs.setStringList(_savedEmailsReporterListKey, _savedReporterEmails.toList());
          await prefs.setString(_savedCredentialsMapReporterKey, _encodeAccountsMap(_savedAccountsReporter, 'reporter'));
        }

        if (_userDatabase.containsKey(emailKey)) {
          _userDatabase[emailKey]!['password_hash'] = _hashPassword(cleanPassword);
        }
        await _saveUserDatabaseToStorage();
      } else {
        // Unchecked Save Account -> Remove credentials ONLY from targetRole!
        await clearSavedCredentials(targetRole);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error saving credentials: $e');
    }
  }

  /// Clear all saved credentials from memory and storage ONLY for the specified role
  Future<void> clearSavedCredentials([String? role]) async {
    try {
      final targetRole = (role ?? _selectedRole).toLowerCase();
      final prefs = await SharedPreferences.getInstance();

      if (targetRole == 'community') {
        _savedEmailCommunity = null;
        _savedPasswordCommunity = null;
        _savedCommunityEmails.clear();
        _savedAccountsCommunity.clear();
        _rememberMeCommunity = false;

        await prefs.remove(_savedEmailCommunityKey);
        await prefs.remove(_savedPasswordCommunityKey);
        await prefs.remove(_savedCredentialsMapCommunityKey);
        await prefs.remove(_savedEmailsCommunityListKey);
        await prefs.setBool(_rememberMeCommunityKey, false);
      } else {
        _savedEmailReporter = null;
        _savedPasswordReporter = null;
        _savedReporterEmails.clear();
        _savedAccountsReporter.clear();
        _rememberMeReporter = false;

        await prefs.remove(_savedEmailReporterKey);
        await prefs.remove(_savedPasswordReporterKey);
        await prefs.remove(_savedCredentialsMapReporterKey);
        await prefs.remove(_savedEmailsReporterListKey);
        await prefs.setBool(_rememberMeReporterKey, false);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error clearing saved credentials for $role: $e');
    }
  }

  /// Remove a specific saved account permanently from saved accounts list and storage for a role
  Future<void> removeSavedAccount(String email, [String? role]) async {
    try {
      final cleanEmail = email.trim();
      final emailKey = cleanEmail.toLowerCase();
      final targetRole = (role ?? _selectedRole).toLowerCase();

      _removedAccounts.add(_removedKey(targetRole, emailKey));
      final prefs = await SharedPreferences.getInstance();

      final removedList = _removedAccounts.toList();
      await prefs.setStringList(_removedAccountsKey, removedList);
      await prefs.setString(_removedAccountsJsonKey, jsonEncode(removedList));

      if (targetRole == 'community') {
        _savedCommunityEmails.removeWhere((e) => e.trim().toLowerCase() == emailKey);
        await prefs.setStringList(_savedEmailsCommunityListKey, _savedCommunityEmails.toList());
        _savedAccountsCommunity.removeWhere((k, v) => k.trim().toLowerCase() == emailKey);
        await prefs.setString(_savedCredentialsMapCommunityKey, _encodeAccountsMap(_savedAccountsCommunity, 'community'));
        if (_savedEmailCommunity?.trim().toLowerCase() == emailKey) {
          _savedEmailCommunity = null;
          _savedPasswordCommunity = null;
          await prefs.remove(_savedEmailCommunityKey);
          await prefs.remove(_savedPasswordCommunityKey);
        }
      } else {
        _savedReporterEmails.removeWhere((e) => e.trim().toLowerCase() == emailKey);
        await prefs.setStringList(_savedEmailsReporterListKey, _savedReporterEmails.toList());
        _savedAccountsReporter.removeWhere((k, v) => k.trim().toLowerCase() == emailKey);
        await prefs.setString(_savedCredentialsMapReporterKey, _encodeAccountsMap(_savedAccountsReporter, 'reporter'));
        if (_savedEmailReporter?.trim().toLowerCase() == emailKey) {
          _savedEmailReporter = null;
          _savedPasswordReporter = null;
          await prefs.remove(_savedEmailReporterKey);
          await prefs.remove(_savedPasswordReporterKey);
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error removing saved account: $e');
    }
  }

  Future<void> _saveUserDatabaseToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_dbStorageKey, jsonEncode(_userDatabase));
      await prefs.setString(_roleStorageKey, _selectedRole);

      if (_currentUser != null) {
        await prefs.setString(_sessionStorageKey, jsonEncode(_currentUser!.toJson()));
      } else {
        await prefs.remove(_sessionStorageKey);
      }
    } catch (e) {
      debugPrint('Error saving user database to storage: $e');
    }
  }

  // OTP Verification & Password Reset state
  String? _pendingOtp;
  Map<String, String>? _pendingRegistrationData;

  String? _pendingSignInOtp;
  Map<String, String>? _pendingSignInCredentials;

  String? _pendingResetEmail;
  String? _pendingResetCode;
  DateTime? _resetCodeExpiry;
  bool _isResetCodeVerified = false;
  final Set<String> _usedResetCodes = {};

  UserModel? get currentUser => _currentUser;
  String get selectedRole => _selectedRole;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _currentUser != null;
  String? get errorMessage => _errorMessage;
  String? get pendingOtp => _pendingOtp;
  String? get pendingSignInOtp => _pendingSignInOtp;
  String? get pendingResetCode => _pendingResetCode;
  String? get pendingResetEmail => _pendingResetEmail;
  bool get isResetCodeVerified => _isResetCodeVerified;

  @visibleForTesting
  void setCurrentUserForTesting(UserModel? user) {
    _currentUser = user;
    if (user != null) {
      _selectedRole = user.role;
    }
    notifyListeners();
  }

  /// Strict ownership check using authenticated user ID and complaint's creator/reporter ID stored in Supabase.
  bool isComplaintOwner(dynamic complaintObj) {
    if (_currentUser == null) return false;
    final authUserId = _currentUser!.id.trim().toLowerCase();
    if (authUserId.isEmpty) return false;

    String complaintReporterId = '';
    if (complaintObj is Complaint) {
      complaintReporterId = complaintObj.reporterId.trim().toLowerCase();
    } else if (complaintObj is Map) {
      complaintReporterId = (complaintObj['reporter_id'] ?? complaintObj['user_id'] ?? '').toString().trim().toLowerCase();
    }

    if (complaintReporterId.isEmpty) return false;
    return authUserId == complaintReporterId;
  }


  void setSelectedRole(String role) async {
    _selectedRole = role;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_roleStorageKey, role);
    } catch (_) {}
    await _saveUserDatabaseToStorage();
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Completely remove and wipe all registered emails, saved accounts, and user database
  Future<void> removeAllRegisteredUsers() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      _userDatabase.clear();
      _savedAccountsReporter.clear();
      _savedAccountsCommunity.clear();
      _savedReporterEmails.clear();
      _savedCommunityEmails.clear();
      _removedAccounts.clear();

      _savedEmailReporter = null;
      _savedPasswordReporter = null;
      _savedEmailCommunity = null;
      _savedPasswordCommunity = null;
      _rememberMeReporter = true;
      _rememberMeCommunity = true;
      _currentUser = null;

      await prefs.remove(_dbStorageKey);
      await prefs.remove(_sessionStorageKey);
      await prefs.remove(_savedEmailReporterKey);
      await prefs.remove(_savedPasswordReporterKey);
      await prefs.remove(_savedCredentialsMapReporterKey);
      await prefs.remove(_savedEmailsReporterListKey);
      await prefs.remove(_rememberMeReporterKey);

      await prefs.remove(_savedEmailCommunityKey);
      await prefs.remove(_savedPasswordCommunityKey);
      await prefs.remove(_savedCredentialsMapCommunityKey);
      await prefs.remove(_savedEmailsCommunityListKey);
      await prefs.remove(_rememberMeCommunityKey);

      await prefs.remove(_savedCredentialsMapLegacyKey);
      await prefs.remove(_legacyEmailKey);
      await prefs.remove(_legacyPasswordKey);
      await prefs.remove(_legacyRememberMeKey);
      await prefs.remove(_removedAccountsKey);
      await prefs.remove(_removedAccountsJsonKey);

      notifyListeners();
    } catch (e) {
      debugPrint('Error removing all registered users: $e');
    }
  }

  /// Clear all saved accounts permanently from storage for target role or all roles
  Future<void> clearAllSavedAccounts([String? role]) async {
    try {
      if (role == null) {
        await removeAllRegisteredUsers();
        return;
      }

      final targetRole = role.toLowerCase();
      final prefs = await SharedPreferences.getInstance();

      if (targetRole == 'community') {
        _savedAccountsCommunity.clear();
        _savedCommunityEmails.clear();
        _savedEmailCommunity = null;
        _savedPasswordCommunity = null;
        _rememberMeCommunity = false;
        await prefs.remove(_savedEmailCommunityKey);
        await prefs.remove(_savedPasswordCommunityKey);
        await prefs.remove(_savedCredentialsMapCommunityKey);
        await prefs.remove(_savedEmailsCommunityListKey);
        await prefs.setBool(_rememberMeCommunityKey, false);

        // Remove community users from _userDatabase
        _userDatabase.removeWhere((k, v) => v['role']?.toLowerCase() == 'community');
      } else {
        _savedAccountsReporter.clear();
        _savedReporterEmails.clear();
        _savedEmailReporter = null;
        _savedPasswordReporter = null;
        _rememberMeReporter = false;
        await prefs.remove(_savedEmailReporterKey);
        await prefs.remove(_savedPasswordReporterKey);
        await prefs.remove(_savedCredentialsMapReporterKey);
        await prefs.remove(_savedEmailsReporterListKey);
        await prefs.setBool(_rememberMeReporterKey, false);

        // Remove reporter users from _userDatabase
        _userDatabase.removeWhere((k, v) => v['role']?.toLowerCase() == 'reporter' || v['role'] == null);
      }

      await _saveUserDatabaseToStorage();
      notifyListeners();
    } catch (e) {
      debugPrint('Error clearing saved accounts: $e');
    }
  }

  String _hashPassword(String password) {
    // Secure salt + iterative FNV-1a rounds for password hashing (no plain text in hash)
    const salt = 'roadwatch_sec_v3_salt_994827158392';
    final bytes = utf8.encode('$salt:$password');
    int h1 = 0x811c9dc5;
    int h2 = 0x27d4eb2f;
    for (int i = 0; i < bytes.length; i++) {
      int b = bytes[i];
      h1 = ((h1 ^ b) * 0x01000193) & 0xFFFFFFFF;
      h2 = ((h2 ^ (b + i)) * 0x050c5d1d) & 0xFFFFFFFF;
    }
    for (int r = 0; r < 50; r++) {
      h1 = ((h1 ^ (h2 >> 3)) * 0x01000193) & 0xFFFFFFFF;
      h2 = ((h2 ^ (h1 >> 5)) * 0x050c5d1d) & 0xFFFFFFFF;
    }
    return 'rw_sec_${h1.toRadixString(16).padLeft(8, '0')}_${h2.toRadixString(16).padLeft(8, '0')}';
  }

  /// Helper to verify password against stored credentials (with hash migration support)
  bool _verifyPassword(String inputPassword, Map<String, String> userData) {
    final registeredPassword = userData['password'];
    final registeredHash = userData['password_hash'];
    final inputHash = _hashPassword(inputPassword);

    if (registeredHash != null && registeredHash == inputHash) {
      return true;
    }
    if (registeredHash != null && registeredHash.contains(inputPassword)) {
      // Migrate legacy hash string format
      userData['password_hash'] = inputHash;
      userData.remove('password');
      return true;
    }
    if (registeredPassword != null && registeredPassword == inputPassword) {
      // Migrate plain text entry
      userData['password_hash'] = inputHash;
      userData.remove('password');
      return true;
    }
    return false;
  }

  /// Helper to find password in a map using case-insensitive email key search
  String? _findPasswordInMap(Map<String, String> map, String emailKey) {
    for (var entry in map.entries) {
      if (entry.key.trim().toLowerCase() == emailKey) {
        return entry.value;
      }
    }
    return null;
  }

  /// Check whether an account is permanently registered in the authentication system or database
  Future<bool> _isAccountRegistered(String email, [String? role]) async {
    await _ensureStorageLoaded();

    final cleanEmail = email.trim().toLowerCase();
    final targetRole = role?.trim().toLowerCase();

    // 1. Check local persistent authentication database (_userDatabase)
    final localData = _userDatabase[cleanEmail];
    if (localData != null) {
      final isVerified = localData['is_verified'] == 'true' || localData['is_verified'] == '1';
      if (isVerified) {
        final localRole = localData['role']?.toString().toLowerCase();
        if (targetRole == null || localRole == targetRole) {
          return true;
        }
      }
    }

    // 2. Check saved email sets
    if (targetRole == 'community') {
      if (_savedCommunityEmails.contains(cleanEmail) || _savedAccountsCommunity.containsKey(cleanEmail)) {
        return true;
      }
    } else if (targetRole == 'reporter') {
      if (_savedReporterEmails.contains(cleanEmail) || _savedAccountsReporter.containsKey(cleanEmail)) {
        return true;
      }
    } else {
      if (_savedReporterEmails.contains(cleanEmail) ||
          _savedCommunityEmails.contains(cleanEmail) ||
          _savedAccountsReporter.containsKey(cleanEmail) ||
          _savedAccountsCommunity.containsKey(cleanEmail)) {
        return true;
      }
    }

    // 3. Check Supabase profiles table if connected
    if (SupabaseService.isConnected) {
      final isSupaReg = await SupabaseService.isEmailRegistered(cleanEmail, role: targetRole);
      if (isSupaReg) {
        return true;
      }
    }

    return false;
  }

  /// Sign In User directly with Email and Password
  Future<bool> signIn({required String email, required String password, String? role}) async {
    await _ensureStorageLoaded();

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 200));

    final cleanEmail = email.trim();
    final cleanPassword = password.trim();

    if (cleanEmail.isEmpty || cleanPassword.isEmpty) {
      _errorMessage = 'Please enter both email and password.';
      _isLoading = false;
      notifyListeners();
      return false;
    }

    final emailKey = cleanEmail.toLowerCase();
    final targetRole = (role ?? _selectedRole).trim().toLowerCase();

    bool authenticated = false;
    String? userId;
    String? userName;
    String? userPhone;
    String? userAvatar;
    String? storedRole;
    String? authExceptionMsg;

    // 1. PRIMARY AUTHENTICATION VIA SUPABASE AUTH (IF CONNECTED)
    if (SupabaseService.isConnected) {
      try {
        final supaRes = await SupabaseService.login(
          email: cleanEmail,
          password: cleanPassword,
        );

        if (supaRes != null && supaRes.user != null) {
          final supaUser = supaRes.user!;
          userId = supaUser.id;

          String? metaName;
          if (supaUser.userMetadata != null) {
            final candidateKeys = ['name', 'full_name', 'display_name', 'username', 'user_name'];
            for (var k in candidateKeys) {
              final v = supaUser.userMetadata![k];
              if (v != null) {
                final s = v.toString().trim();
                if (s.isNotEmpty && !s.contains('@') && s != 'Registered Voter' && s != 'Registered User') {
                  metaName = s;
                  break;
                }
              }
            }
          }

          userName = metaName ?? _userDatabase[emailKey]?['name']?.toString();
          userPhone = supaUser.phone ?? supaUser.userMetadata?['phone'] ?? '';

          // Validate account role against authoritative profile source
          final metaRole = supaUser.userMetadata?['role']?.toString().trim().toLowerCase();
          final trustedRole = await SupabaseService.fetchUserRole(userId, email: cleanEmail);
          storedRole = trustedRole ?? (metaRole == 'reporter' || metaRole == 'community' ? metaRole : null);

          // REJECT UNKNOWN / MISSING ROLES - DO NOT SILENTLY DEFAULT TO REPORTER
          if (storedRole == null || storedRole.isEmpty || (storedRole != 'reporter' && storedRole != 'community')) {
            await SupabaseService.logout();
            _isLoading = false;
            _errorMessage = 'Account role is unassigned or invalid (${storedRole ?? "none"}). Please contact support or re-register.';
            notifyListeners();
            return false;
          }

          // Authoritative role from user_profiles table
          // Adopt the user's verified role directly and route accordingly
          final verifiedRole = storedRole;
          _selectedRole = verifiedRole;

          authenticated = true;

          // Ensure user profile in Supabase profiles database table (Safely ignore profile write errors to preserve session)
          try {
            await SupabaseService.ensureUserProfile(
              userId: supaUser.id,
              email: cleanEmail,
              role: storedRole,
              name: userName,
              phone: userPhone,
            );
          } catch (e) {
            debugPrint('Notice: Profile sync error ignored to preserve auth session: $e');
          }
        }
      } on AuthException catch (e) {
        authExceptionMsg = e.message;
        final msgLower = e.message.toLowerCase();
        final codeLower = (e.code ?? '').toLowerCase();
        debugPrint('Supabase AuthException on signIn: ${e.message} (code: ${e.code}, status: ${e.statusCode})');

        if (SupabaseService.isRateLimitException(e)) {
          _errorMessage = SupabaseService.formatAuthErrorMessage(e);
        } else if (msgLower.contains('email not confirmed') || codeLower.contains('email_not_confirmed')) {
          _errorMessage = 'Email not confirmed. Please check your inbox or click resend.';
        } else if (msgLower.contains('invalid login credentials') || codeLower.contains('invalid_credentials') || msgLower.contains('invalid grant')) {
          final isRegistered = await _isAccountRegistered(cleanEmail);
          if (isRegistered) {
            _errorMessage = 'Incorrect email or password. Please try again.';
          } else {
            _errorMessage = 'Account not registered. Please sign up first.';
          }
        } else {
          _errorMessage = e.message;
        }
      } catch (e) {
        debugPrint('Supabase login error: $e');
        _errorMessage = 'Authentication error: $e';
      }
    }

    // 2. FALLBACK/SYNC WITH LOCAL USER DATABASE IF SUPABASE WAS NOT CONNECTED OR OFFLINE
    var userData = _userDatabase[emailKey];

    if (!authenticated && _errorMessage == null) {
      if (userData != null) {
        final isPasswordCorrect = _verifyPassword(cleanPassword, userData);
        if (isPasswordCorrect) {
          storedRole = userData['role']?.toString().toLowerCase();
          storedRole ??= targetRole;

          if (storedRole != targetRole) {
            _isLoading = false;
            if (storedRole == 'reporter' && targetRole == 'community') {
              _errorMessage = 'This account is registered as a Reporter. Please sign in through the Reporter Portal.';
            } else if (storedRole == 'community' && targetRole == 'reporter') {
              _errorMessage = 'This account is registered as a Community User. Please sign in through the Community Portal.';
            } else {
              _errorMessage = 'This account is registered as a ${storedRole == "reporter" ? "Reporter" : "Community User"}. Please sign in through the matching portal.';
            }
            notifyListeners();
            return false;
          }

          authenticated = true;
          userId = userData['id'] ?? 'usr_${DateTime.now().millisecondsSinceEpoch}';
          userName = (userData['name'] != null && userData['name'].toString().trim().isNotEmpty && !userData['name'].toString().contains('@'))
              ? userData['name'].toString().trim()
              : null;
          userPhone = userData['phone'] ?? '';
          userAvatar = userData['avatar_url'];
        } else {
          // Registered email locally, but wrong password
          _errorMessage = 'Incorrect email or password. Please try again.';
          _isLoading = false;
          notifyListeners();
          return false;
        }
      }
    }

    // 3. IF STILL NOT AUTHENTICATED
    if (!authenticated) {
      if (_errorMessage == null) {
        if (authExceptionMsg != null && SupabaseService.isRateLimitException(authExceptionMsg)) {
          _errorMessage = SupabaseService.formatAuthErrorMessage(authExceptionMsg);
        } else if (authExceptionMsg != null && (authExceptionMsg.toLowerCase().contains('email not confirmed') || authExceptionMsg.toLowerCase().contains('email_not_confirmed'))) {
          _errorMessage = 'Email not confirmed. Please check your inbox or click resend.';
        } else {
          final isRegistered = await _isAccountRegistered(cleanEmail);

          if (isRegistered) {
            _errorMessage = 'Incorrect email or password. Please try again.';
          } else {
            _errorMessage = 'Account not registered. Please sign up first.';
          }
        }
      }

      _isLoading = false;
      notifyListeners();
      return false;
    }

    // 4. AUTHENTICATION SUCCESSFUL!
    final verifiedRole = storedRole ?? targetRole;
    final validName = (userName != null && userName.trim().isNotEmpty && !userName.contains('@')) ? userName.trim() : null;

    userData ??= {
      'id': userId!,
      'name': validName ?? '',
      'email': cleanEmail,
      'phone': userPhone ?? '',
      'password_hash': _hashPassword(cleanPassword),
      'role': verifiedRole,
      'is_verified': 'true',
    };
    userData['role'] = verifiedRole;
    if (validName != null) {
      userData['name'] = validName;
    }
    _userDatabase[emailKey] = userData;

    _currentUser = UserModel(
      id: userId!,
      name: validName ?? 'Registered User',
      email: cleanEmail,
      phone: userPhone ?? '',
      role: verifiedRole,
      avatarUrl: (userAvatar != null && userAvatar.trim().isNotEmpty) ? userAvatar.trim() : null,
      isVerified: true,
    );

    // Save or update saved account credentials list based on role-specific rememberMe state
    await saveCredentials(
      email: cleanEmail,
      password: cleanPassword,
      rememberMe: getRememberMe(verifiedRole),
      role: verifiedRole,
    );

    await _saveUserDatabaseToStorage();

    _isLoading = false;
    notifyListeners();
    return true;
  }

  /// Quick Register & Sign In for users whose account session wasn't found
  Future<bool> quickRegisterAndSignIn({
    required String email,
    required String password,
    String? name,
    String? role,
  }) async {
    await _ensureStorageLoaded();

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 400));

    final cleanEmail = email.trim();
    final cleanPassword = password.trim();

    if (cleanEmail.isEmpty || cleanPassword.isEmpty) {
      _errorMessage = 'Please enter email and password.';
      _isLoading = false;
      notifyListeners();
      return false;
    }

    final emailKey = cleanEmail.toLowerCase();
    final resolvedRole = (role ?? _selectedRole).trim().toLowerCase();
    final targetRole = (resolvedRole == 'reporter' || resolvedRole == 'community') ? resolvedRole : 'reporter';
    final userId = 'usr_${DateTime.now().millisecondsSinceEpoch}';
    final validName = (name != null && name.trim().isNotEmpty && !name.contains('@')) ? name.trim() : null;

    _userDatabase[emailKey] = {
      'id': userId,
      'name': validName ?? '',
      'email': cleanEmail,
      'phone': '',
      'password_hash': _hashPassword(cleanPassword),
      'role': targetRole,
      'is_verified': 'true',
    };

    _currentUser = UserModel(
      id: userId,
      name: validName ?? 'Reporter name unavailable',
      email: cleanEmail,
      phone: '',
      role: targetRole,
      avatarUrl: _userDatabase[emailKey]?['avatar_url'],
      isVerified: true,
    );

    await saveCredentials(
      email: cleanEmail,
      password: cleanPassword,
      rememberMe: true,
      role: targetRole,
    );

    await _saveUserDatabaseToStorage();
    _isLoading = false;
    notifyListeners();
    return true;
  }

  /// Quick Demo Sign In
  Future<void> signInDemo(String role) async {
    _selectedRole = role;
    if (role == 'reporter') {
      final savedAvatar = _userDatabase['alex.mercer@citizen.org']?['avatar_url'];
      _currentUser = UserModel(
        id: 'user_rep_1',
        name: 'Alex Mercer',
        email: 'alex.mercer@citizen.org',
        phone: '',
        role: 'reporter',
        avatarUrl: savedAvatar ?? 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=400&auto=format&fit=crop',
      );
    } else {
      final savedAvatar = _userDatabase['mark.repair@community.org']?['avatar_url'];
      _currentUser = UserModel(
        id: 'comm_user_1',
        name: 'Volunteer Squad Lead - Mark',
        email: 'mark.repair@community.org',
        phone: '',
        role: 'community',
        avatarUrl: savedAvatar ?? 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=400&auto=format&fit=crop',
      );
    }
    await _saveUserDatabaseToStorage();
    notifyListeners();
  }

  // OTP Expiration state
  DateTime? _pendingOtpExpiry;

  /// Initiate Registration: Stores pending data and sends EmailJS OTP
  Future<bool> initiateRegistration({
    required String name,
    required String email,
    String? phone = '',
    required String password,
    required String role,
  }) async {
    await _ensureStorageLoaded();

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final cleanName = name.trim();
    final cleanEmail = email.trim();
    final cleanPhone = (phone ?? '').trim();
    final cleanPassword = password.trim();

    final emailKey = cleanEmail.toLowerCase();
    final targetRole = role.trim().toLowerCase();

    if (targetRole != 'reporter' && targetRole != 'community') {
      _errorMessage = 'Invalid account role: $role. Must be reporter or community.';
      _isLoading = false;
      notifyListeners();
      return false;
    }

    // Block registration if account is already registered under ANY role
    final isAnyRegistered = await _isAccountRegistered(cleanEmail);

    if (isAnyRegistered) {
      final existingRole = await SupabaseService.getStoredRoleForEmail(cleanEmail) ?? _userDatabase[emailKey]?['role'];
      if (existingRole == 'reporter') {
        _errorMessage = 'This email is already registered as a Reporter account. Please sign in with your Reporter account.';
      } else if (existingRole == 'community') {
        _errorMessage = 'This email is already registered as a Community account. Please sign in with your Community account.';
      } else {
        _errorMessage = 'Account already registered with this email. Please sign in instead.';
      }
      _isLoading = false;
      notifyListeners();
      return false;
    }

    // Generate random 6-digit OTP
    final random = Random();
    final otp = (100000 + random.nextInt(900000)).toString();
    _pendingOtp = otp;
    _pendingOtpExpiry = DateTime.now().add(const Duration(minutes: 15));
    _pendingRegistrationData = {
      'name': cleanName,
      'email': cleanEmail,
      'phone': cleanPhone,
      'password': cleanPassword,
      'role': targetRole,
    };

    // Trigger EmailJS Email Service
    final emailSent = await EmailService.sendOtpEmail(
      userEmail: cleanEmail,
      userName: cleanName,
      otpCode: otp,
    );

    if (!emailSent) {
      debugPrint('EmailJS OTP Notice: ${EmailService.lastError}');
    }

    _isLoading = false;
    notifyListeners();
    return true;
  }

  /// Resend Registration OTP code to pending user
  Future<bool> resendRegistrationOtp() async {
    if (_pendingRegistrationData == null) {
      _errorMessage = 'No pending registration found. Please fill out the sign up form again.';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final data = _pendingRegistrationData!;
    final random = Random();
    final otp = (100000 + random.nextInt(900000)).toString();
    _pendingOtp = otp;
    _pendingOtpExpiry = DateTime.now().add(const Duration(minutes: 15));

    final emailSent = await EmailService.sendOtpEmail(
      userEmail: data['email']!,
      userName: data['name']!,
      otpCode: otp,
    );

    _isLoading = false;
    notifyListeners();
    return emailSent;
  }

  /// Verify 6-digit OTP Code and Complete User Registration
  Future<bool> verifyOtpAndCompleteSignup(String enteredOtp) async {
    await _ensureStorageLoaded();

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 300));

    final entered = enteredOtp.trim();

    if (_pendingOtp == null || _pendingRegistrationData == null) {
      _errorMessage = 'No pending registration found. Please sign up again.';
      _isLoading = false;
      notifyListeners();
      return false;
    }

    if (_pendingOtpExpiry != null && DateTime.now().isAfter(_pendingOtpExpiry!)) {
      _errorMessage = 'Verification code expired. Please request a new code.';
      _isLoading = false;
      notifyListeners();
      return false;
    }

    if (entered != _pendingOtp) {
      _errorMessage = 'Invalid verification code. Please try again.';
      _isLoading = false;
      notifyListeners();
      return false;
    }

    if (_pendingRegistrationData != null) {
      final data = _pendingRegistrationData!;
      final cleanEmail = data['email']!.trim();
      final emailKey = cleanEmail.toLowerCase();
      final targetRole = data['role']!.trim().toLowerCase();
      String userId = 'usr_${DateTime.now().millisecondsSinceEpoch}';

      // 1. PRIMARY: REGISTER ACCOUNT IN SUPABASE AUTH (IF CONNECTED)
      if (SupabaseService.isConnected) {
        try {
          final supaRes = await SupabaseService.signUp(
            email: cleanEmail,
            password: data['password']!,
            data: {
              'name': data['name']!,
              'full_name': data['name']!,
              'display_name': data['name']!,
              'phone': data['phone']!,
              'role': targetRole,
            },
          );

          if (supaRes != null && supaRes.user != null) {
            userId = supaRes.user!.id;

            // Ensure user profile record in Supabase profiles table
            await SupabaseService.ensureUserProfile(
              userId: userId,
              email: cleanEmail,
              role: targetRole,
              name: data['name']!,
              phone: data['phone']!,
            );
          } else {
            _errorMessage = 'Failed to create user account in Supabase. Please try again.';
            _isLoading = false;
            notifyListeners();
            return false;
          }
        } on AuthException catch (e) {
          debugPrint('Supabase AuthException on signUp: ${e.message} (code: ${e.code}, status: ${e.statusCode})');
          if (SupabaseService.isRateLimitException(e)) {
            _errorMessage = SupabaseService.formatAuthErrorMessage(e);
          } else if (e.message.toLowerCase().contains('already registered') || (e.code ?? '').toLowerCase() == 'user_already_exists') {
            _errorMessage = 'An account with this email is already registered. Please sign in instead.';
          } else {
            _errorMessage = e.message;
          }
          _isLoading = false;
          notifyListeners();
          return false;
        } catch (e) {
          debugPrint('Supabase signUp error: $e');
          _errorMessage = 'Registration error: ${e.toString()}';
          _isLoading = false;
          notifyListeners();
          return false;
        }
      }

      // 2. Create account entry in local database cache (_userDatabase)
      _userDatabase[emailKey] = {
        'id': userId,
        'name': data['name']!,
        'email': cleanEmail,
        'phone': data['phone']!,
        'password_hash': _hashPassword(data['password']!),
        'role': targetRole,
        'is_verified': 'true',
      };

      _currentUser = null; // Do not sign in automatically; user signs in on Sign In page
      _pendingOtp = null;
      _pendingOtpExpiry = null;
      _pendingRegistrationData = null;

      // 3. Save user database permanently to SharedPreferences
      await _saveUserDatabaseToStorage();

      // 4. Save credentials into saved accounts map permanently if rememberMe is enabled for target role
      if (getRememberMe(targetRole)) {
        await saveCredentials(
          email: cleanEmail,
          password: data['password']!,
          rememberMe: true,
          role: targetRole,
        );
      }
    }

    _isLoading = false;
    notifyListeners();
    return true;
  }

  /// Resend Supabase email confirmation with rate-limit protection & error messaging
  Future<bool> resendConfirmationEmail(String email) async {
    final cleanEmail = email.trim();
    if (cleanEmail.isEmpty) {
      _errorMessage = 'Please enter a valid email address.';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final result = await SupabaseService.resendConfirmationEmail(email: cleanEmail);

    _isLoading = false;
    if (result['success'] == true) {
      _errorMessage = null;
      notifyListeners();
      return true;
    } else {
      _errorMessage = result['message'] ?? 'Failed to resend confirmation email.';
      notifyListeners();
      return false;
    }
  }

  /// Update User Profile
  Future<void> updateProfile({
    String? name,
    String? phone,
    String? avatarUrl,
  }) async {
    if (_currentUser == null) return;

    final cleanName = name?.trim();
    final cleanPhone = phone?.trim();

    String updatedName = _currentUser!.name;
    if (cleanName != null && cleanName.isNotEmpty && !cleanName.contains('@')) {
      updatedName = cleanName;
    }

    _currentUser = _currentUser!.copyWith(
      name: updatedName,
      phone: (cleanPhone != null && cleanPhone.isNotEmpty) ? cleanPhone : _currentUser!.phone,
      avatarUrl: avatarUrl ?? _currentUser!.avatarUrl,
    );

    // Also update in registered users database
    final emailKey = _currentUser!.email.trim().toLowerCase();
    if (_userDatabase.containsKey(emailKey)) {
      _userDatabase[emailKey]!['name'] = updatedName;
      if (cleanPhone != null && cleanPhone.isNotEmpty) {
        _userDatabase[emailKey]!['phone'] = cleanPhone;
      }
      if (_currentUser!.avatarUrl != null) {
        _userDatabase[emailKey]!['avatar_url'] = _currentUser!.avatarUrl!;
      }
    }

    if (SupabaseService.isConnected) {
      await SupabaseService.ensureUserProfile(
        userId: _currentUser!.id,
        email: _currentUser!.email,
        role: _currentUser!.role,
        name: updatedName,
        phone: cleanPhone ?? _currentUser!.phone,
      );
    }

    await _saveUserDatabaseToStorage();
    notifyListeners();
  }

  /// Logout User completely from Supabase and active local session
  Future<void> logout([String? targetRole]) async {
    _currentUser = null;
    if (targetRole != null) {
      _selectedRole = targetRole;
    }
    try {
      if (SupabaseService.isConnected) {
        await SupabaseService.logout();
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_sessionStorageKey);
    } catch (e) {
      debugPrint('Error during logout: $e');
    }
    notifyListeners();
  }

  /// Delete Reporter Account completely from authentication system, storage, memory, and backend
  Future<bool> deleteReporterAccount() async {
    await _ensureStorageLoaded();

    final userToDelete = _currentUser;
    final email = userToDelete?.email.trim() ?? _savedEmailReporter?.trim();
    if (email == null || email.isEmpty) {
      return false;
    }

    final emailKey = email.toLowerCase();
    final prefs = await SharedPreferences.getInstance();

    // 1. Permanently delete Reporter entry from _userDatabase (only if role is reporter)
    if (_userDatabase.containsKey(emailKey)) {
      final userRole = _userDatabase[emailKey]?['role']?.toString().toLowerCase();
      if (userRole == 'reporter' || userRole == null) {
        _userDatabase.remove(emailKey);
      }
    }

    // 2. Remove from Reporter saved accounts list and saved credentials
    _savedAccountsReporter.removeWhere((k, v) => k.trim().toLowerCase() == emailKey);
    await prefs.setString(_savedCredentialsMapReporterKey, _encodeAccountsMap(_savedAccountsReporter, 'reporter'));

    if (_savedEmailReporter?.trim().toLowerCase() == emailKey) {
      _savedEmailReporter = null;
      _savedPasswordReporter = null;
      await prefs.remove(_savedEmailReporterKey);
      await prefs.remove(_savedPasswordReporterKey);
    }

    // 3. Clear legacy single saved credentials if matching
    final legacyEmail = prefs.getString(_legacyEmailKey);
    if (legacyEmail?.trim().toLowerCase() == emailKey) {
      await prefs.remove(_legacyEmailKey);
      await prefs.remove(_legacyPasswordKey);
    }

    // 4. Add to removed accounts blacklist to avoid restoring from any legacy storage maps
    _removedAccounts.add(_removedKey('reporter', emailKey));
    final removedList = _removedAccounts.toList();
    await prefs.setStringList(_removedAccountsKey, removedList);
    await prefs.setString(_removedAccountsJsonKey, jsonEncode(removedList));

    // 5. Delete Supabase Auth user and associated data if connected
    if (SupabaseService.isConnected) {
      await SupabaseService.deleteAccount();
    }

    // 6. Clear active session & user state completely (unauthenticate user)
    _currentUser = null;
    _selectedRole = 'reporter';
    _errorMessage = null;
    await prefs.remove(_sessionStorageKey);

    // 7. Save updated _userDatabase to SharedPreferences
    await _saveUserDatabaseToStorage();

    notifyListeners();
    return true;
  }

  /// Send Password Reset Link / Code via EmailJS
  Future<bool> sendPasswordResetLink(String email) async {
    await _ensureStorageLoaded();

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final cleanEmail = email.trim();
    if (cleanEmail.isEmpty) {
      _errorMessage = 'Please enter your registered email address.';
      _isLoading = false;
      notifyListeners();
      return false;
    }

    final emailKey = cleanEmail.toLowerCase();
    final targetRole = _selectedRole.toLowerCase();
    final userData = _userDatabase[emailKey];
    final isRegistered = await _isAccountRegistered(cleanEmail, targetRole);

    if (!isRegistered) {
      _errorMessage = 'Account not registered. Please sign up first.';
      _isLoading = false;
      notifyListeners();
      return false;
    }

    // Generate random 6-digit reset code
    final random = Random();
    final resetCode = (100000 + random.nextInt(900000)).toString();
    _pendingResetEmail = cleanEmail;
    _pendingResetCode = resetCode;
    _resetCodeExpiry = DateTime.now().add(const Duration(minutes: 15));
    _isResetCodeVerified = false;

    final name = userData?['name'] ?? cleanEmail.split('@').first;

    final emailSent = await EmailService.sendOtpEmail(
      userEmail: cleanEmail,
      userName: name,
      otpCode: resetCode,
    );

    if (!emailSent) {
      debugPrint('EmailJS Password Reset Notice: ${EmailService.lastError}');
    }

    _isLoading = false;
    notifyListeners();
    return true;
  }

  /// Verify 6-digit Password Reset Code (Step 2)
  Future<bool> verifyPasswordResetCode({
    required String email,
    required String code,
  }) async {
    await _ensureStorageLoaded();

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 300));

    final cleanEmail = email.trim().toLowerCase();
    final cleanCode = code.trim();

    if (_pendingResetCode == null ||
        _pendingResetEmail == null ||
        cleanEmail != _pendingResetEmail!.toLowerCase()) {
      _errorMessage = 'Invalid reset code. Please try again.';
      _isLoading = false;
      notifyListeners();
      return false;
    }

    if (_usedResetCodes.contains(cleanCode)) {
      _errorMessage = 'Invalid reset code. Please try again.';
      _isLoading = false;
      notifyListeners();
      return false;
    }

    if (_resetCodeExpiry != null && DateTime.now().isAfter(_resetCodeExpiry!)) {
      _errorMessage = 'Reset code expired. Please request a new code.';
      _isLoading = false;
      notifyListeners();
      return false;
    }

    if (cleanCode != _pendingResetCode) {
      _errorMessage = 'Invalid reset code. Please try again.';
      _isLoading = false;
      notifyListeners();
      return false;
    }

    _isResetCodeVerified = true;
    _isLoading = false;
    notifyListeners();
    return true;
  }

  /// Confirm Password Reset with New Password & Confirmation (Step 3 & 4)
  Future<bool> confirmPasswordReset({
    required String email,
    required String newPassword,
    required String confirmPassword,
    String? code,
  }) async {
    await _ensureStorageLoaded();

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 300));

    final cleanEmail = email.trim();
    final emailKey = cleanEmail.toLowerCase();
    final cleanNewPass = newPassword.trim();
    final cleanConfirmPass = confirmPassword.trim();

    if (cleanNewPass != cleanConfirmPass) {
      _errorMessage = 'Passwords do not match.';
      _isLoading = false;
      notifyListeners();
      return false;
    }

    if (cleanNewPass.length < 6) {
      _errorMessage = 'Password must be at least 6 characters long.';
      _isLoading = false;
      notifyListeners();
      return false;
    }

    if (!_isResetCodeVerified || _pendingResetEmail == null || emailKey != _pendingResetEmail!.toLowerCase()) {
      _errorMessage = 'Reset code not verified. Please verify your code first.';
      _isLoading = false;
      notifyListeners();
      return false;
    }

    final isRegistered = await _isAccountRegistered(cleanEmail, _selectedRole);
    if (!isRegistered) {
      _errorMessage = 'Account not registered. Please sign up first.';
      _isLoading = false;
      notifyListeners();
      return false;
    }

    // Mark reset code as used to prevent reuse
    if (_pendingResetCode != null) {
      _usedResetCodes.add(_pendingResetCode!);
    }

    // Update password permanently in user database with new secure hash
    _userDatabase[emailKey] ??= {};
    _userDatabase[emailKey]!.remove('password');
    _userDatabase[emailKey]!['password_hash'] = _hashPassword(cleanNewPass);
    _userDatabase[emailKey]!['is_verified'] = 'true';

    final prefs = await SharedPreferences.getInstance();

    // Update saved account entries if present so auto sign-in uses new password securely
    if (_savedAccountsReporter.containsKey(cleanEmail) || _savedAccountsReporter.containsKey(emailKey)) {
      _savedAccountsReporter[cleanEmail] = cleanNewPass;
      _savedAccountsReporter[emailKey] = cleanNewPass;
      await prefs.setString(_savedCredentialsMapReporterKey, _encodeAccountsMap(_savedAccountsReporter, 'reporter'));
    }
    if (_savedAccountsCommunity.containsKey(cleanEmail) || _savedAccountsCommunity.containsKey(emailKey)) {
      _savedAccountsCommunity[cleanEmail] = cleanNewPass;
      _savedAccountsCommunity[emailKey] = cleanNewPass;
      await prefs.setString(_savedCredentialsMapCommunityKey, _encodeAccountsMap(_savedAccountsCommunity, 'community'));
    }

    if (_savedEmailReporter?.toLowerCase() == emailKey) {
      _savedPasswordReporter = cleanNewPass;
      await prefs.setString(_savedPasswordReporterKey, _encryptPassword(cleanNewPass, 'reporter', _savedEmailReporter!));
    }
    if (_savedEmailCommunity?.toLowerCase() == emailKey) {
      _savedPasswordCommunity = cleanNewPass;
      await prefs.setString(_savedPasswordCommunityKey, _encryptPassword(cleanNewPass, 'community', _savedEmailCommunity!));
    }

    // Sync updated password to Supabase if connected
    if (SupabaseService.isConnected) {
      try {
        await SupabaseService.client?.auth.updateUser(UserAttributes(password: cleanNewPass));
      } catch (e) {
        debugPrint('Notice syncing updated password to Supabase: $e');
      }
    }

    await _saveUserDatabaseToStorage();

    _pendingResetCode = null;
    _pendingResetEmail = null;
    _resetCodeExpiry = null;
    _isResetCodeVerified = false;

    _isLoading = false;
    notifyListeners();
    return true;
  }
}
