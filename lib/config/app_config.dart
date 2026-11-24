import 'package:flutter/foundation.dart';

class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const apkDownloadUrl = String.fromEnvironment(
    'APK_DOWNLOAD_URL',
    defaultValue:
        'https://drive.google.com/drive/folders/1Gu9zumhtxd5vQlQ8RHpZdzTxUInZMAkQ?usp=drive_link',
  );
  static const _proxyUrl = String.fromEnvironment('GEMINI_PROXY_URL');
  static const _nativeUrl = String.fromEnvironment('NATIVE_API_URL');

  static bool get usesSupabase =>
      supabaseUrl.startsWith('https://') && supabaseKey.isNotEmpty;

  static Uri? get apkDownloadUri {
    final uri = Uri.tryParse(apkDownloadUrl);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      return null;
    }
    return uri;
  }

  static Uri get apiBase => usesSupabase
      ? Uri.parse('$supabaseUrl/functions/v1/planova-api/')
      : geminiEndpoint.resolve('./');

  static Uri get geminiEndpoint {
    if (usesSupabase) return apiBase.resolve('generate');
    if (kIsWeb) return Uri.base.resolve('/api/gemini');
    if (_nativeUrl.isNotEmpty) return Uri.parse(_nativeUrl);
    if (_proxyUrl.isNotEmpty) return Uri.parse(_proxyUrl);
    final host = defaultTargetPlatform == TargetPlatform.android
        ? '10.0.2.2'
        : '127.0.0.1';
    return Uri.parse('http://$host:8787/api/gemini');
  }
}
