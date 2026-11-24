import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

http.Client createClient() =>
    BrowserClient()..withCredentials = !AppConfig.usesSupabase;
