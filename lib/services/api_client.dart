import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import 'platform_http_native.dart'
    if (dart.library.js_interop) 'platform_http_web.dart'
    as platform;

class ApiException implements Exception {
  final int status;
  final String message;
  const ApiException(this.status, this.message);
  @override
  String toString() => message;
}

class ApiClient {
  static final shared = ApiClient();
  final http.Client _http;
  final Uri _base;
  String? token;
  VoidCallback? onUnauthorized;
  ApiClient({http.Client? client, Uri? base})
    : _http = client ?? platform.createClient(),
      _base = base ?? AppConfig.apiBase;

  Future<http.Response> postRaw(
    Uri uri,
    Map<String, String> headers,
    String body,
  ) async {
    final response = await _http
        .post(
          uri,
          headers: {
            ...headers,
            if (AppConfig.usesSupabase) 'apikey': AppConfig.supabaseKey,
            if (token != null) 'Authorization': 'Bearer $token',
          },
          body: body,
        )
        .timeout(const Duration(seconds: 50));
    if (response.statusCode == 401) onUnauthorized?.call();
    return response;
  }

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? data,
  }) async {
    try {
      final request = http.Request(method, _base.resolve(path));
      request.headers.addAll({
        'Accept': 'application/json',
        if (AppConfig.usesSupabase) 'apikey': AppConfig.supabaseKey,
        if (!kIsWeb) 'X-Planner-Client': 'native',
        if (token != null) 'Authorization': 'Bearer $token',
        if (data != null) 'Content-Type': 'application/json; charset=utf-8',
      });
      if (data != null) request.body = jsonEncode(data);
      final response = await http.Response.fromStream(
        await _http.send(request).timeout(const Duration(seconds: 35)),
      ).timeout(const Duration(seconds: 35));
      Map<String, dynamic> body;
      try {
        body =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      } catch (_) {
        throw const ApiException(
          502,
          'The server returned an invalid response.',
        );
      }
      if (response.statusCode >= 400) {
        if (response.statusCode == 401 &&
            (!path.startsWith('auth/') || path == 'auth/me')) {
          onUnauthorized?.call();
        }
        throw ApiException(
          response.statusCode,
          body['error'] is String
              ? body['error'] as String
              : 'Please try again.',
        );
      }
      return body;
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException(
        0,
        'Cannot reach the server. Check your connection and try again.',
      );
    }
  }
}
