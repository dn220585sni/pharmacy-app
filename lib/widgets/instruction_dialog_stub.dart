import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Desktop/mobile implementation — shows instruction in a popup dialog
/// with parsed HTML content (UTF-8 decoded).
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
  bool _loading = true;
  String? _error;
  List<_Section> _sections = [];

  @override
  void initState() {
    super.initState();
    _loadInstruction();
  }

  Future<void> _loadInstruction() async {
    try {
      final response = await http.Client()
          .get(Uri.parse(widget.url))
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (response.statusCode != 200) {
        setState(() {
          _loading = false;
          _error = 'Помилка завантаження (${response.statusCode})';
        });
        return;
      }

      final html = utf8.decode(response.bodyBytes);
      final sections = _parseHtml(html);

      if (!mounted) return;
      setState(() {
        _sections = sections;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Не вдалось завантажити інструкцію';
      });
    }
  }

  /// Parse HTML into sections (h2 headers + body text).
  List<_Section> _parseHtml(String html) {
    // Extract body content
    final bodyMatch = RegExp(r'<body[^>]*>(.*)</body>', dotAll: true)
        .firstMatch(html);
    final body = bodyMatch?.group(1) ?? html;

    // Split by h2 headers
    final parts = body.split(RegExp(r'<h2[^>]*>', caseSensitive: false));
    final sections = <_Section>[];

    for (final part in parts) {
      if (part.trim().isEmpty) continue;

      final h2End = part.indexOf('</h2>');
      String title = '';
      String content = part;

      if (h2End >= 0) {
        title = _stripTags(part.substring(0, h2End)).trim();
        content = part.substring(h2End + 5);
      }

      final text = _stripTags(content).trim();
      if (text.isNotEmpty || title.isNotEmpty) {
        sections.add(_Section(title: title, body: text));
      }
    }

    return sections;
  }

  /// Remove HTML tags and decode common entities.
  String _stripTags(String html) {
    return html
        .replaceAll(RegExp(r'<br\s*/?>'), '\n')
        .replaceAll(RegExp(r'<li[^>]*>'), '\n• ')
        .replaceAll(RegExp(r'</p>'), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&mdash;', '—')
        .replaceAll('&ndash;', '–')
        .replaceAll('&laquo;', '«')
        .replaceAll('&raquo;', '»')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Dialog(
      insetPadding: const EdgeInsets.all(32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: size.width * 0.55,
        height: size.height * 0.85,
        child: Column(
          children: [
            // Title bar
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
                    tooltip: 'Закрити (Esc)',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Content
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
                  : _error != null
                      ? Center(
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              color: Color(0xFF9CA3AF),
                              fontSize: 14,
                            ),
                          ),
                        )
                      : _buildContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      itemCount: _sections.length,
      itemBuilder: (context, index) {
        final section = _sections[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (section.title.isNotEmpty) ...[
                Text(
                  section.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E7DC8),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 6),
              ],
              if (section.body.isNotEmpty)
                Text(
                  section.body,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF1C1C2E),
                    height: 1.6,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Section {
  final String title;
  final String body;
  const _Section({required this.title, required this.body});
}
