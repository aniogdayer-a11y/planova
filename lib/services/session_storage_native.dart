import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/app_config.dart';

const _storage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  ),
);
String get _key =>
    'planner.session.${base64UrlEncode(utf8.encode(AppConfig.apiBase.toString()))}';
Future<String?> readSession() => _storage.read(key: _key);
Future<void> writeSession(String value) =>
    _storage.write(key: _key, value: value);
Future<void> clearSession() => _storage.delete(key: _key);
