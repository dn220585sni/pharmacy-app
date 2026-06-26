import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Підпис запитів до Спарти (ЛАЙК), розділ 1.6.3 «Requests signing».
///
/// Двоступеневий SHA256 (НЕ HMAC):
///   signatureBase = SHA256(ланцюг_полів)
///   signature     = SHA256(signatureBase + posKey)
/// обидва — hex-рядки в нижньому регістрі.
///
/// Ланцюг збирається зі значень обраних полів (порядок — per-operation) за
/// правилами конвертації [encodeString]/[encodeBool]/[encodeNumber]/[encodeDateMs].
class SpartaSignature {
  /// Обчислити підпис: SHA256(SHA256(chain) + posKey).
  static String compute(String chain, String posKey) {
    final base = sha256.convert(utf8.encode(chain)).toString();
    return sha256.convert(utf8.encode('$base$posKey')).toString();
  }

  /// Зібрати ланцюг із частин (конкатенація без роздільників).
  static String chain(Iterable<String> parts) => parts.join();

  // ── Конвертація значень у текст для підпису (правила 1.6.3) ───────────────

  /// String — без змін; null → порожній рядок.
  static String encodeString(String? v) => v ?? '';

  /// Boolean — true → '1', false/null → '' (false == відсутність поля).
  static String encodeBool(bool? v) => v == true ? '1' : '';

  /// Double/Integer — значення ×100, ЦІЛА частина (обрізання до коп., НЕ
  /// округлення: 20.1678 → '2016'); від'ємні з мінусом. null → ''.
  /// Епсилон прибирає плаваючу похибку (20.56·100 = 2055.9999… → '2056').
  static String encodeNumber(num? v) {
    if (v == null) return '';
    final cents = (v.abs() * 100 + 1e-6).floor();
    if (cents == 0) return '0';
    return v < 0 ? '-$cents' : '$cents';
  }

  /// Date — timestamp у мілісекундах (з 1970, з урахуванням TZ). null → ''.
  static String encodeDateMs(DateTime? d) =>
      d == null ? '' : d.millisecondsSinceEpoch.toString();
}
