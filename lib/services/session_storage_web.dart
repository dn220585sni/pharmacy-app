// Web platform — session storage uses localStorage.
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

const _key = 'pharmacy_session';

String? getSession() => html.window.localStorage[_key];

void saveSession(String sessionId, String user) {
  html.window.localStorage[_key] = '$sessionId\n$user';
}

void clearSession() {
  html.window.localStorage.remove(_key);
}
