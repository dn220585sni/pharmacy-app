# Налаштування dev-середовища на Windows ВМ (10.90.77.66)

## Що отримаємо
- Flutter Windows desktop додаток (.exe) — запускається подвійним кліком
- Немає CORS — native HTTP, всі сервіси працюють (Caché, anc.ua, Skarb)
- Немає проблем з path_provider, dart:io, файлами
- Claude Code для розробки — працюємо так само як на Mac
- Git — pull змін з GitHub

---

## Крок 1: Встановити Git

Відкрити PowerShell **як адміністратор**:

```powershell
winget install Git.Git
```

Або завантажити вручну: https://git-scm.com/download/win

Після встановлення **закрити і відкрити PowerShell заново**.

Перевірка:
```powershell
git --version
```

---

## Крок 2: Встановити Visual Studio 2022

Потрібен для компіляції Windows desktop додатків.

1. Завантажити **Visual Studio 2022 Community** (безкоштовна):
   https://visualstudio.microsoft.com/downloads/

2. При встановленні обрати **один** компонент:
   - ✅ **Desktop development with C++**

   Решту не потрібно — ні .NET, ні ASP.NET, ні Azure.

3. Встановити (займе ~8 ГБ, 10-15 хвилин)

---

## Крок 3: Встановити Flutter SDK

1. Завантажити Flutter SDK для Windows:
   https://docs.flutter.dev/get-started/install/windows/desktop

2. Розпакувати в `D:\flutter`

3. Додати в PATH — в PowerShell (адмін):
```powershell
[Environment]::SetEnvironmentVariable("Path", $env:Path + ";D:\flutter\bin", "Machine")
```

4. **Закрити і відкрити PowerShell заново**.

Перевірка:
```powershell
flutter --version
flutter doctor
```

`flutter doctor` має показати:
```
[✓] Flutter
[✓] Windows Version
[✓] Visual Studio - develop Windows apps
```

Warnings про Android Studio, Chrome — ігноруйте.

---

## Крок 4: Встановити Node.js (для Claude Code)

```powershell
winget install OpenJS.NodeJS.LTS
```

Або завантажити: https://nodejs.org/ (LTS версія)

**Закрити і відкрити PowerShell заново**.

Перевірка:
```powershell
node --version
npm --version
```

---

## Крок 5: Встановити Claude Code

```powershell
npm install -g @anthropic-ai/claude-code
```

Перевірка:
```powershell
claude --version
```

---

## Крок 6: Клонувати репозиторій

```powershell
cd D:\
git clone https://github.com/dn220585sni/pharmacy-app.git
cd pharmacy-app
```

Встановити Flutter залежності:
```powershell
flutter pub get
```

---

## Крок 7: Перший build + запуск

Зібрати Windows desktop додаток:
```powershell
flutter build windows --release
```

Запустити:
```powershell
.\build\windows\x64\runner\Release\pharmacy_app.exe
```

Або знайти файл в Провіднику:
```
D:\pharmacy-app\build\windows\x64\runner\Release\pharmacy_app.exe
```

Подвійний клік — додаток запускається.

### Створити ярлик на робочому столі (опціонально)

```powershell
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut("$env:USERPROFILE\Desktop\Pharmacy App.lnk")
$Shortcut.TargetPath = "D:\pharmacy-app\build\windows\x64\runner\Release\pharmacy_app.exe"
$Shortcut.WorkingDirectory = "D:\pharmacy-app\build\windows\x64\runner\Release"
$Shortcut.IconLocation = "D:\pharmacy-app\build\windows\x64\runner\Release\pharmacy_app.exe,0"
$Shortcut.Save()
```

---

## Крок 8: Створити deploy скрипт (одноразово)

Зберегти як `D:\pharmacy-app\deploy.ps1`:

```powershell
# deploy.ps1 — Build Windows desktop app & run
$ErrorActionPreference = "Stop"
Set-Location "D:\pharmacy-app"

Write-Host "Building Windows desktop app..." -ForegroundColor Cyan
flutter build windows --release

Write-Host ""
Write-Host "Build complete!" -ForegroundColor Green

# Auto-run
Write-Host "Starting app..." -ForegroundColor Cyan
Start-Process "D:\pharmacy-app\build\windows\x64\runner\Release\pharmacy_app.exe"
```

Тепер build + запуск — одна команда:
```powershell
cd D:\pharmacy-app
.\deploy.ps1
```

---

## Крок 9: Робота з Claude Code

```powershell
cd D:\pharmacy-app
claude
```

Все працює як на Mac — Claude Code має доступ до файлів, може редагувати, збирати, деплоїти.

---

## Щоденний workflow

```powershell
cd D:\pharmacy-app

# 1. Підтягнути останні зміни з GitHub
git pull

# 2. Запустити Claude Code для розробки
claude

# 3. Після змін — build + запуск
.\deploy.ps1

# 4. Закомітити і запушити
git add -A
git commit -m "опис змін"
git push
```

---

## Примітки

- **CORS**: Windows desktop додаток — native HTTP, CORS не існує.
  Всі сервіси працюють: Caché, anc.ua аналоги, Skarb, Priority Analogs
- **ApiConfig.baseUrl**: можна залишити `http://10.90.77.66:57772/csp/user/Kab.Service.cls`
  або змінити на `http://localhost:57772/csp/user/Kab.Service.cls`
- **path_provider**: працює нормально на Windows — сесії зберігаються у файл
- **Flutter doctor warnings**: про Android Studio, Chrome — ігноруйте,
  для Windows desktop потрібен тільки Visual Studio з C++
- **Debug mode**: для швидкої розробки можна використовувати `flutter run -d windows`
  замість `flutter build` — hot reload працює
