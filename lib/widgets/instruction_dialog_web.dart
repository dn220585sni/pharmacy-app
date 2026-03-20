import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Tracks which view types have already been registered.
final _registeredViewTypes = <String>{};

/// Monotonically increasing counter to guarantee unique view types.
int _nextId = 0;

/// Web implementation — shows instruction in an embedded iframe dialog.
void showInstructionDialog(BuildContext context, String url) {
  showDialog(
    context: context,
    builder: (ctx) => _InstructionDialog(url: url),
  );
}

class _InstructionDialog extends StatefulWidget {
  final String url;
  const _InstructionDialog({required this.url});

  @override
  State<_InstructionDialog> createState() => _InstructionDialogState();
}

class _InstructionDialogState extends State<_InstructionDialog> {
  late final String _viewType;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _viewType = 'instruction-iframe-${_nextId++}';
    _loadAndRegister();
  }

  Future<void> _loadAndRegister() async {
    // Fetch HTML as bytes and decode as UTF-8
    String htmlContent;
    try {
      final response = await http.Client()
          .get(Uri.parse(widget.url))
          .timeout(const Duration(seconds: 10));
      htmlContent = utf8.decode(response.bodyBytes);
    } catch (_) {
      // Fallback: let browser handle it via src
      htmlContent = '';
    }

    if (!mounted) return;

    final useSrcdoc = htmlContent.isNotEmpty;
    // Wrap with proper charset meta + basic styling
    final fullHtml = useSrcdoc
        ? '<!DOCTYPE html><html><head><meta charset="utf-8">'
            '<style>body{font-family:system-ui,sans-serif;font-size:14px;'
            'line-height:1.6;padding:24px;color:#1C1C2E;max-width:900px;margin:0 auto}'
            'h2{font-size:16px;color:#1E7DC8;margin-top:20px}'
            'p{margin:6px 0}</style></head><body>$htmlContent</body></html>'
        : '';

    if (!_registeredViewTypes.contains(_viewType)) {
      final url = widget.url;
      ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
        final iframe = html.IFrameElement()
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%';
        if (useSrcdoc) {
          iframe.srcdoc = fullHtml;
        } else {
          iframe.src = url;
        }
        return iframe;
      });
      _registeredViewTypes.add(_viewType);
    }

    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Dialog(
      insetPadding: const EdgeInsets.all(32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: size.width * 0.75,
        height: size.height * 0.85,
        child: Column(
          children: [
            // ── Title bar ──
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: const BoxDecoration(
                color: Color(0xFFF8F9FB),
                border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
              ),
              child: Row(
                children: [
                  const Icon(Icons.description_rounded,
                      size: 18, color: Color(0xFF1E7DC8)),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Інструкція до препарату',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1C1C2E),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        size: 20, color: Color(0xFF6B7280)),
                    splashRadius: 16,
                    tooltip: 'Закрити',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // ── Content ──
            Expanded(
              child: _loading
                  ? const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF1E7DC8),
                        ),
                      ),
                    )
                  : HtmlElementView(viewType: _viewType),
            ),
          ],
        ),
      ),
    );
  }
}
