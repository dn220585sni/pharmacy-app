/// Напрям службової операції каси (для `NameWorkRRO`).
enum CashDirection {
  cashIn('In', 'Внесення'),
  cashOut('Out', 'Винесення');

  const CashDirection(this.param, this.label);

  /// Значення `NameWorkRRO` для бекенду.
  final String param;

  /// Підпис для UI.
  final String label;
}

/// Мапінг причин (бекенд російською — legacy Delphi) → українські підписи для UI.
/// У `SaveSumDay` слати ОРИГІНАЛЬНУ назву (ключ), не переклад.
const Map<String, String> _reasonUa = {
  'Служебное внесение': 'Службове внесення',
  'Внесение разменных купюр': 'Внесення розмінних купюр',
  'Возврат суммы по инкассации': 'Повернення суми по інкасації',
  'Возврат украденных средств': 'Повернення вкрадених коштів',
  'Инкассация': 'Інкасація',
  'Ошибка вноса выноса': 'Помилка внесення/винесення',
  'Кража': 'Крадіжка',
  'Инкассация в кассу предприятия': 'Інкасація в касу підприємства',
  'Инкассация-обналичивание Приват': 'Інкасація-видача готівки Приват',
  'Инкассация-обналичивание Ощад': 'Інкасація-видача готівки Ощад',
  'Инкассация-обналичивание Пумб': 'Інкасація-видача готівки ПУМБ',
};

/// Український підпис причини для відображення (fallback — оригінал).
String cashReasonUa(String backendName) => _reasonUa[backendName] ?? backendName;

/// Розпарсити відповідь `GetOperKassa` → список назв причин (оригінальних).
/// `{"Status":"OK","Reasons":[{"name":"Инкассация"}, ...]}`
List<String> parseCashReasons(dynamic data) {
  final raw = (data is Map) ? data['Reasons'] : null;
  if (raw is! List) return const [];
  return raw
      .whereType<Map<String, dynamic>>()
      .map((j) => j['name']?.toString() ?? '')
      .where((s) => s.isNotEmpty)
      .toList(growable: false);
}
