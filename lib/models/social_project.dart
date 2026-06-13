/// Соц-проект з API `GetSpisSocProject` (або local fallback).
///
/// Сервер повертає список доступних на конкретній аптеці. Деякі програми
/// (Пакунок малюка, Дарниця +, Армія+, єПідтримка, Нацкешбек) додаються
/// локально завжди — поки не з'являться на сервері.
class SocialProject {
  /// Назва для відображення в UI. Може бути перевизначена через
  /// `_displayNameOverrides` у `SocialProjectsService` (наприклад
  /// "Ебот кард" → "Медикард", "Реімбурсація" → "Доступні ліки").
  final String name;

  /// Серверний tag для передачі як `nameProject` у GetSumSkid.
  /// `null` для local-only (поки програма не на сервері).
  final String? tag;

  /// Чи додано локально (не з сервера). Інформативно — для діагностики.
  final bool isLocal;

  const SocialProject({
    required this.name,
    this.tag,
    this.isLocal = false,
  });
}
