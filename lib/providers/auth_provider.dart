import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';
import '../services/api_client.dart';
import '../services/session_storage_native.dart'
    if (dart.library.js_interop) '../services/session_storage_web.dart'
    as storage;

class AccountUser {
  final String id, email, name;
  const AccountUser({
    required this.id,
    required this.email,
    required this.name,
  });
  factory AccountUser.fromMap(Map<String, dynamic> value) => AccountUser(
    id: value['id'] as String,
    email: value['email'] as String,
    name: value['name'] as String,
  );
}

class AuthProvider extends ChangeNotifier {
  final ApiClient api;
  final Future<String?> Function() _readToken;
  final Future<void> Function(String) _writeToken;
  final Future<void> Function() _clearToken;
  late final Future<void> ready;
  AccountUser? user;
  bool initializing = true, busy = false;
  String? error, challengeId, message;
  DateTime? resendAt;
  String _email = '', _name = '', _purpose = 'login', _password = '';
  bool _disposed = false, _expiring = false;
  bool get _hosted => AppConfig.usesSupabase;
  SupabaseClient get _supabase => Supabase.instance.client;
  AuthProvider({
    ApiClient? client,
    Future<String?> Function()? readToken,
    Future<void> Function(String)? writeToken,
    Future<void> Function()? clearToken,
  }) : api = client ?? ApiClient.shared,
       _readToken = readToken ?? storage.readSession,
       _writeToken = writeToken ?? storage.writeSession,
       _clearToken = clearToken ?? storage.clearSession {
    api.onUnauthorized = () {
      if (!initializing) unawaited(expire());
    };
    ready = initialize();
  }
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    initializing = true;
    error = null;
    _notify();
    try {
      if (_hosted) {
        final current = _supabase.auth.currentUser;
        if (current != null) {
          api.token = _supabase.auth.currentSession?.accessToken;
          user = AccountUser(
            id: current.id,
            email: current.email ?? '',
            name:
                (current.userMetadata?['name'] as String?) ??
                current.email?.split('@').first ??
                'Planova',
          );
        }
        return;
      }
      api.token = await _readToken();
      final response = await api.request('GET', 'auth/me');
      user = AccountUser.fromMap(response['user'] as Map<String, dynamic>);
    } on ApiException catch (e) {
      user = null;
      if (e.status == 401) {
        api.token = null;
        await _clearToken();
      } else {
        error = e.message;
      }
    } catch (_) {
      user = null;
      error = 'Could not restore your session. Please sign in again.';
    } finally {
      initializing = false;
      _notify();
    }
  }

  Future<bool> requestCode({
    required String email,
    required bool createAccount,
    String name = '',
    String password = '',
    bool resetPassword = false,
  }) async {
    if (busy) return false;
    busy = true;
    error = null;
    _notify();
    try {
      if (_hosted) {
        final cleanEmail = email.trim();
        _email = cleanEmail;
        _name = name.trim();
        _purpose = resetPassword
            ? 'reset'
            : createAccount
            ? 'register'
            : 'login';
        _password = password;
        if (resetPassword) {
          await _supabase.auth.resetPasswordForEmail(cleanEmail);
        } else if (createAccount) {
          final response = await _supabase.auth.signUp(
            email: cleanEmail,
            password: password,
            data: {'name': _name},
          );
          if (response.session != null) {
            await _supabase.auth.signOut(scope: SignOutScope.local);
          }
        } else {
          await _supabase.auth.signInWithPassword(
            email: cleanEmail,
            password: password,
          );
          await _supabase.auth.signOut(scope: SignOutScope.local);
          await _supabase.auth.signInWithOtp(
            email: cleanEmail,
            shouldCreateUser: false,
          );
        }
        challengeId = 'supabase-$_purpose';
        resendAt = DateTime.now().add(const Duration(seconds: 60));
        message = null;
        return true;
      }
      final response = await api.request(
        'POST',
        'auth/request-code',
        data: {
          'email': email.trim(),
          'name': name.trim(),
          'purpose': resetPassword
              ? 'reset'
              : createAccount
              ? 'register'
              : 'login',
          if (!resetPassword) 'password': password,
        },
      );
      _email = email.trim();
      _name = name.trim();
      _purpose = resetPassword
          ? 'reset'
          : createAccount
          ? 'register'
          : 'login';
      _password = password;
      message = null;
      challengeId = response['challengeId'] as String;
      resendAt = DateTime.now().add(
        Duration(seconds: response['retryAfter'] as int),
      );
      return true;
    } on AuthException catch (e) {
      error = e.message;
      return false;
    } on ApiException catch (e) {
      error = e.message;
      return false;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<bool> resend() async {
    if (_hosted && _purpose == 'register') {
      if (busy) return false;
      busy = true;
      error = null;
      _notify();
      try {
        await _supabase.auth.resend(type: OtpType.signup, email: _email);
        resendAt = DateTime.now().add(const Duration(seconds: 60));
        return true;
      } on AuthException catch (e) {
        error = e.message;
        return false;
      } finally {
        busy = false;
        _notify();
      }
    }
    return requestCode(
      email: _email,
      name: _name,
      createAccount: _purpose == 'register',
      resetPassword: _purpose == 'reset',
      password: _password,
    );
  }

  Future<bool> verify(String code) async {
    if (busy || challengeId == null) return false;
    busy = true;
    error = null;
    _notify();
    try {
      if (_hosted) {
        final response = await _supabase.auth.verifyOTP(
          email: _email,
          token: code.trim(),
          type: _purpose == 'register' ? OtpType.signup : OtpType.email,
        );
        final current = response.user;
        if (current == null || response.session == null) {
          throw const AuthException('This code is incorrect or expired.');
        }
        api.token = response.session!.accessToken;
        user = AccountUser(
          id: current.id,
          email: current.email ?? _email,
          name:
              (current.userMetadata?['name'] as String?) ??
              (_name.isEmpty ? _email.split('@').first : _name),
        );
        challengeId = null;
        _password = '';
        return true;
      }
      final response = await api.request(
        'POST',
        'auth/verify',
        data: {'challengeId': challengeId, 'code': code.trim()},
      );
      if (!kIsWeb) {
        final token = response['token'] as String;
        await _writeToken(token);
        api.token = token;
      }
      user = AccountUser.fromMap(response['user'] as Map<String, dynamic>);
      challengeId = null;
      _password = '';
      return true;
    } on AuthException catch (e) {
      error = e.message;
      return false;
    } on ApiException catch (e) {
      error = e.message;
      return false;
    } catch (_) {
      error =
          'Could not securely save your session. Please try signing in again.';
      return false;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<bool> resetPassword(String code, String password) async {
    if (busy || challengeId == null) return false;
    busy = true;
    error = null;
    _notify();
    try {
      if (_hosted) {
        await _supabase.auth.verifyOTP(
          email: _email,
          token: code.trim(),
          type: OtpType.recovery,
        );
        await _supabase.auth.updateUser(UserAttributes(password: password));
        await _supabase.auth.signOut(scope: SignOutScope.global);
        api.token = null;
        user = null;
        _password = '';
        challengeId = null;
        message = 'Password updated. Sign in with your new password.';
        return true;
      }
      final result = await api.request(
        'POST',
        'auth/reset-password',
        data: {
          'challengeId': challengeId,
          'code': code.trim(),
          'password': password,
        },
      );
      api.token = null;
      await _clearToken();
      user = null;
      _password = '';
      challengeId = null;
      message =
          result['message'] as String? ?? 'Password updated. Sign in again.';
      return true;
    } on AuthException catch (e) {
      error = e.message;
      return false;
    } on ApiException catch (e) {
      error = e.message;
      return false;
    } catch (_) {
      error = 'Password updated. Please restart the app and sign in again.';
      return false;
    } finally {
      busy = false;
      _notify();
    }
  }

  void changeEmail() {
    challengeId = null;
    resendAt = null;
    _password = '';
    error = null;
    message = null;
    _notify();
  }

  Future<void> logout() async {
    if (busy) return;
    busy = true;
    _notify();
    try {
      if (_hosted) {
        await _supabase.auth.signOut();
        api.token = null;
        user = null;
        _password = '';
        challengeId = null;
        error = null;
        return;
      }
      await api.request('POST', 'auth/logout', data: {});
      api.token = null;
      await _clearToken();
      user = null;
      _password = '';
      challengeId = null;
      error = null;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> expire() async {
    if (_expiring) return;
    _expiring = true;
    try {
      api.token = null;
      try {
        await _clearToken();
      } catch (_) {}
      user = null;
      _password = '';
      challengeId = null;
      error = 'Your session expired. Please sign in again.';
      _notify();
    } finally {
      _expiring = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    api.onUnauthorized = null;
    super.dispose();
  }
}
