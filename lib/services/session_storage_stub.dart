// Stub for non-web platforms — session storage uses File (path_provider).

String? getSession() => null;
void saveSession(String sessionId, String user) {}
void clearSession() {}
