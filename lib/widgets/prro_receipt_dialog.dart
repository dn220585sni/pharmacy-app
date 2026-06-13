import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/prro_service.dart';

/// Повноцінний preview фіскального чеку: текст, QR, номер, посилання.
/// Закривається автоматично через [autoCloseAfter].
class PrroReceiptDialog extends StatefulWidget {
  final PrroResult result;
  final VoidCallback? onClose;
  final Duration autoCloseAfter;

  const PrroReceiptDialog({
    super.key,
    required this.result,
    this.onClose,
    this.autoCloseAfter = const Duration(seconds: 3),
  });

  static Future<void> show(BuildContext context, PrroResult result) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PrroReceiptDialog(result: result),
    );
  }

  @override
  State<PrroReceiptDialog> createState() => _PrroReceiptDialogState();
}

class _PrroReceiptDialogState extends State<PrroReceiptDialog> {
  Timer? _autoCloseTimer;

  @override
  void initState() {
    super.initState();
    _autoCloseTimer = Timer(widget.autoCloseAfter, () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _autoCloseTimer?.cancel();
    super.dispose();
  }

  PrroResult get result => widget.result;

  String? get _textDecoded {
    final raw = result.textPrint;
    if (raw == null || raw.isEmpty) return null;
    try {
      return utf8.decode(base64Decode(raw));
    } catch (_) {
      return raw;
    }
  }

  Uint8List? get _qrBytes {
    final raw = result.qrBase64;
    if (raw == null || raw.isEmpty) return null;
    try {
      return base64Decode(raw);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final qr = _qrBytes;
    final text = _textDecoded;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context),
              const SizedBox(height: 14),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (text != null) _receiptText(text),
                      if (qr != null) ...[
                        const SizedBox(height: 16),
                        _qrBlock(qr),
                      ],
                      if (result.link != null && result.link!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _linkBlock(context, result.link!),
                      ],
                      if (result.isOffline) ...[
                        const SizedBox(height: 12),
                        _offlineBadge(),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _actions(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: Color(0xFFD1FAE5),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                color: Color(0xFF10B981),
                size: 36,
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Text(
                'Оплата проведена',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF065F46),
                  height: 1.1,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 22),
              onPressed: () => Navigator.of(context).pop(),
              tooltip: 'Закрити',
            ),
          ],
        ),
        if (result.orderNum != null)
          Padding(
            padding: const EdgeInsets.only(left: 62, top: 2),
            child: Text(
              'Чек № ${result.orderNum}',
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF64748B),
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
      ],
    );
  }

  Widget _receiptText(String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: SelectableText(
        text,
        style: const TextStyle(
          fontFamily: 'Courier',
          fontSize: 11.5,
          height: 1.35,
          color: Color(0xFF0F172A),
        ),
      ),
    );
  }

  Widget _qrBlock(Uint8List bytes) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Center(
        child: Image.memory(
          bytes,
          width: 180,
          height: 180,
          fit: BoxFit.contain,
          gaplessPlayback: true,
        ),
      ),
    );
  }

  Widget _linkBlock(BuildContext context, String url) {
    return InkWell(
      onTap: () => _openLink(context, url),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFBFDBFE)),
        ),
        child: Row(
          children: [
            const Icon(Icons.link, size: 18, color: Color(0xFF2563EB)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF2563EB),
                  fontSize: 12,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.copy, size: 16),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
              tooltip: 'Скопіювати',
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: url));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Посилання скопійовано'),
                      duration: Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _offlineBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFCD34D)),
      ),
      child: const Row(
        children: [
          Icon(Icons.cloud_off, size: 16, color: Color(0xFFB45309)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Чек створено в офлайн-режимі. Буде передано в податкову після відновлення зв\'язку.',
              style: TextStyle(fontSize: 12, color: Color(0xFF78350F)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            widget.onClose?.call();
          },
          child: const Text('Закрити'),
        ),
      ],
    );
  }

  Future<void> _openLink(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не вдалося відкрити посилання')),
      );
    }
  }
}
