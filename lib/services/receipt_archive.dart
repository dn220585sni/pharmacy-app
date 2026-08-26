import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'fiscal_log.dart';
import 'prro_service.dart';

/// Архів PDF фіскальних чеків.
///
/// Зберігає готовий PDF, який повертає ПРРО у відповіді на `/check/sale`
/// (той самий чек, що показує вікно `PrroReceiptDialog`), у папку **`receipts`**
/// у support-директорії застосунку (`%APPDATA%\com.example\pharmacy_app\receipts`,
/// поряд із `fiscal_log.txt`). Best-effort: збій запису не впливає на продаж.
class ReceiptArchive {
  static const _folderName = 'receipts';

  /// Зберегти PDF успішного чека. Повертає шлях до файлу або `null`.
  static Future<String?> savePdf(PrroResult result) async {
    if (kIsWeb) return null;
    final b64 = result.pdfBase64;
    if (b64 == null || b64.isEmpty) {
      FiscalLog.log('PDF чека відсутній у відповіді ПРРО '
          '(orderNum=${result.orderNum ?? "?"})');
      return null;
    }
    try {
      final dir = await getApplicationSupportDirectory();
      final folder = Directory('${dir.path}/$_folderName');
      if (!await folder.exists()) await folder.create(recursive: true);

      final bytes = base64Decode(b64.trim());
      final file = File('${folder.path}/${_fileName(result)}');
      await file.writeAsBytes(bytes, flush: true);
      FiscalLog.log('PDF чека збережено: ${file.path} (${bytes.length} байт)');
      return file.path;
    } catch (e) {
      FiscalLog.log('PDF чека save FAIL (orderNum=${result.orderNum}): $e');
      return null;
    }
  }

  /// Імʼя файлу: `YYYYMMDD_HHMMSS_<ORDERNUM>.pdf` (сортується за часом).
  static String _fileName(PrroResult result) {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final ts = '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
    final ord = (result.orderNum ?? 'check')
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    return '${ts}_$ord.pdf';
  }
}
