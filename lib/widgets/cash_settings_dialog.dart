import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_config.dart';
import '../services/prro_service.dart';

/// Адмінка «Налаштування каси» — спрощена форма (ПРРО + каса).
/// Поки лише UI: значення на локальному стані; запис у реєстр ZSMU\Farm і
/// читання клієнтів — наступними кроками. Доступ адмін-логінам — згодом.
Future<void> showCashSettingsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _CashSettingsDialog(),
  );
}

class _CashSettingsDialog extends StatefulWidget {
  const _CashSettingsDialog();

  @override
  State<_CashSettingsDialog> createState() => _CashSettingsDialogState();
}

class _CashSettingsDialogState extends State<_CashSettingsDialog> {
  static const _blue = Color(0xFF1E7DC8);
  static const _grey = Color(0xFF6B7280);
  static const _border = Color(0xFFE5E7EB);

  // Каса
  late final _kodKli = TextEditingController(text: ApiConfig.ekkKodKli);
  final _nameKli = TextEditingController();
  String _client = 'АНЦ — Магнолія'; // TODO: список з окремого сервісу

  // ПРРО — зʼєднання (з реєстру; поки дефолти)
  late final _fiscal = TextEditingController(text: '${PrroConfig.numFiscal}');
  late final _smartConnect =
      TextEditingController(text: PrroEnvironment.smartConnectProd.baseUrl);
  final _cloudApi =
      TextEditingController(text: 'https://api.cashdesk.com.ua/api/v2/');

  // ПРРО — доступ
  late final _login = TextEditingController(text: PrroConfig.email);
  late final _password = TextEditingController(text: PrroConfig.password);
  bool _obscure = true;

  // ПРРО — налаштування (вручну)
  String _provider = 'CashDesk'; // TODO: провайдери ПРРО
  final _charCount = TextEditingController(text: '40');
  final _taxGroups = TextEditingController(text: 'ПДВ 7% / ПДВ 20% / без ПДВ');

  @override
  void dispose() {
    for (final c in [
      _kodKli, _nameKli, _fiscal, _smartConnect, _cloudApi,
      _login, _password, _charCount, _taxGroups,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _openCabinet() async {
    final url = PrroService.cabinetUrl();
    final ok = await launchUrl(Uri.parse(url),
        mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Не вдалося відкрити кабінет ПРРО'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  void _save() {
    // TODO: запис у реєстр HKEY_CURRENT_USER\SOFTWARE\ZSMU\Farm (win32_registry).
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Налаштування збережено (UI-демо; запис у реєстр — згодом)'),
      backgroundColor: Color(0xFF16A34A),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  const Icon(Icons.settings_outlined, color: _blue, size: 21),
                  const SizedBox(width: 10),
                  const Text('Налаштування каси',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: _border),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _sectionLabel('Каса'),
                    Row(children: [
                      Expanded(child: _field('Код каси', _kodKli)),
                      const SizedBox(width: 12),
                      Expanded(child: _field('Назва каси', _nameKli)),
                    ]),
                    const SizedBox(height: 10),
                    _label('Клієнт / контрагент'),
                    _dropdown(_client, const ['АНЦ — Магнолія', 'Europharma'],
                        (v) => setState(() => _client = v)),
                    const SizedBox(height: 18),

                    _sectionLabel('ПРРО — зʼєднання'),
                    _field('Фіскальний номер', _fiscal),
                    const SizedBox(height: 10),
                    _field('Сервер SmartConnect', _smartConnect),
                    const SizedBox(height: 10),
                    _field('API ПРРО (cloud)', _cloudApi),
                    const SizedBox(height: 18),

                    _sectionLabel('ПРРО — доступ'),
                    Row(children: [
                      Expanded(child: _field('Логін ПРРО', _login)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _field('Пароль ПРРО', _password,
                            obscure: _obscure,
                            suffix: IconButton(
                              icon: Icon(
                                  _obscure
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  size: 18),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            )),
                      ),
                    ]),
                    const SizedBox(height: 18),

                    _sectionLabel('ПРРО — налаштування'),
                    _label('Провайдер ПРРО (касовий апарат)'),
                    _dropdown(_provider, const ['CashDesk', 'Checkbox'],
                        (v) => setState(() => _provider = v)),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                          child: _field('Кількість символів', _charCount,
                              digits: true)),
                      const SizedBox(width: 12),
                      Expanded(child: _field('Податкові групи', _taxGroups)),
                    ]),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: _border),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
              child: Row(children: [
                OutlinedButton.icon(
                  onPressed: _openCabinet,
                  icon: const Icon(Icons.open_in_new_rounded, size: 17),
                  label: const Text('Стан (кабінет ПРРО)'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _grey,
                    side: const BorderSide(color: _border),
                  ),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Зберегти'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _blue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t.toUpperCase(),
            style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: _grey,
                letterSpacing: 0.4)),
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Text(t, style: const TextStyle(fontSize: 12.5, color: _grey)),
      );

  Widget _field(String label, TextEditingController c,
      {bool obscure = false, bool digits = false, Widget? suffix}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        TextField(
          controller: c,
          obscureText: obscure,
          keyboardType: digits ? TextInputType.number : null,
          inputFormatters:
              digits ? [FilteringTextInputFormatter.digitsOnly] : null,
          style: const TextStyle(fontSize: 13.5),
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            suffixIcon: suffix,
          ),
        ),
      ],
    );
  }

  Widget _dropdown(String value, List<String> items, ValueChanged<String> onCh) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _border),
      ),
      child: DropdownButton<String>(
        value: value,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        style: const TextStyle(fontSize: 13.5, color: Color(0xFF1C1C2E)),
        items: items
            .map((e) => DropdownMenuItem(value: e, child: Text(e)))
            .toList(),
        onChanged: (v) => v == null ? null : onCh(v),
      ),
    );
  }
}
