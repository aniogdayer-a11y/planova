// Browser sessions use HttpOnly cookies. JavaScript never stores the session token.
Future<String?> readSession() async => null;
Future<void> writeSession(String value) async {}
Future<void> clearSession() async {}
