# ФармаПОС (pharmacy_app)

POS-застосунок робочого місця провізора аптеки: продаж, фіскалізація (ПРРО),
лояльність (Sparta/ЛАЙК), каса та зміна. Flutter, десктоп Windows.

**Нові в проекті — почніть звідси: [docs/ONBOARDING.md](docs/ONBOARDING.md)**
(архітектура, головні флоу з діаграмами, глосарій, карта коду, запуск).

## Запуск

```powershell
flutter run -d windows --no-pub --dart-define-from-file=dart_define.json
```

`dart_define.json` — креденшели зовнішніх API (gitignored; шаблон
`dart_define.example.json`). Без цього прапорця ПРРО/лояльність/рецепти
не працюватимуть. Деталі та release-збірка — в [ONBOARDING.md](docs/ONBOARDING.md#2-швидкий-старт-запуск-за-10-хвилин).
