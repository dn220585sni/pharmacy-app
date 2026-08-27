import 'package:flutter/material.dart';
import '../services/auth_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PharmacistPickerDialog — modal dialog for selecting a pharmacist.
// ─────────────────────────────────────────────────────────────────────────────

/// Shows the pharmacist picker dialog and returns the selected pharmacist.
Future<PharmacistInfo?> showPharmacistPicker(
  BuildContext context,
  List<PharmacistInfo> pharmacists,
) {
  return showDialog<PharmacistInfo>(
    context: context,
    builder: (ctx) => PharmacistPickerDialog(pharmacists: pharmacists),
  );
}

class PharmacistPickerDialog extends StatefulWidget {
  final List<PharmacistInfo> pharmacists;
  const PharmacistPickerDialog({super.key, required this.pharmacists});

  @override
  State<PharmacistPickerDialog> createState() =>
      _PharmacistPickerDialogState();
}

class _PharmacistPickerDialogState extends State<PharmacistPickerDialog> {
  final _searchController = TextEditingController();
  final _pinController = TextEditingController();
  final _pinFocusNode = FocusNode();
  List<PharmacistInfo> _filtered = [];

  /// Selected pharmacist awaiting PIN verification (null = list screen).
  PharmacistInfo? _selectedForPin;
  String? _pinError;
  bool _isLoggingIn = false;
  bool _showForceLogout = false;

  @override
  void initState() {
    super.initState();
    _filtered = widget.pharmacists;
    _searchController.addListener(_onSearch);
  }

  void _onSearch() {
    final q = _searchController.text.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filtered = widget.pharmacists;
      } else {
        _filtered = widget.pharmacists
            .where((p) => p.user.toLowerCase().contains(q))
            .toList();
      }
    });
  }

  void _selectForPin(PharmacistInfo p) {
    setState(() {
      _selectedForPin = p;
      _pinController.clear();
      _pinError = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pinFocusNode.requestFocus();
    });
  }

  void _backToList() {
    setState(() {
      _selectedForPin = null;
      _pinController.clear();
      _pinError = null;
    });
  }

  Future<void> _verifyPin() async {
    final p = _selectedForPin;
    if (p == null) return;

    final pin = _pinController.text.trim();
    if (pin.isEmpty) {
      setState(() => _pinError = 'Введіть пароль');
      return;
    }

    // A6: пароль перевіряє ВИКЛЮЧНО сервер (`LoginRlz`). Локального
    // порівняння більше немає — `GetUsersRlz` не віддає `pswd`, і саме тому
    // раніше вхід перестав пускати: клієнт звіряв уведене з порожнім рядком.
    setState(() => _isLoggingIn = true);
    final ok = await AuthService.login(p.user, pin);
    if (!mounted) return;

    if (ok) {
      Navigator.of(context).pop(p);
    } else {
      setState(() {
        _isLoggingIn = false;
        _showForceLogout = AuthService.isUserBusy;
        // Показуємо відповідь сервера як є (напр. «Невірний пароль») — він
        // тепер єдиний, хто знає причину відмови.
        _pinError = AuthService.isUserBusy
            ? 'Сесія вже активна на іншому пристрої'
            : (AuthService.lastLoginError?.trim().isNotEmpty == true
                ? AuthService.lastLoginError!
                : 'Помилка авторизації на сервері');
        if (!AuthService.isUserBusy) {
          _pinController.clear();
          _pinFocusNode.requestFocus();
        }
      });
    }
  }

  /// Примусовий вхід: сервер зачищає УСІ сесії користувача (`LoginRlz&force=1`)
  /// і логінить наново. Спрацьовує лише по кнопці «Завершити сесію».
  Future<void> _cleanupAndRetry() async {
    final p = _selectedForPin;
    if (p == null) return;

    // Той самий пароль, що касир щойно ввів (при «сесія вже активна» поле не
    // очищається) — свого пароля клієнт не має.
    final pin = _pinController.text.trim();
    if (pin.isEmpty) {
      setState(() => _pinError = 'Введіть пароль');
      _pinFocusNode.requestFocus();
      return;
    }

    setState(() {
      _isLoggingIn = true;
      _pinError = null;
      _showForceLogout = false;
    });

    final ok = await AuthService.login(p.user, pin, force: true);
    if (!mounted) return;

    if (ok) {
      Navigator.of(context).pop(p);
    } else {
      setState(() {
        _isLoggingIn = false;
        _pinError = AuthService.lastLoginError ?? 'Не вдалося увійти';
        _showForceLogout = AuthService.isUserBusy;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _pinController.dispose();
    _pinFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Container(
        width: 420,
        height: 500,
        padding: const EdgeInsets.all(0),
        child: _selectedForPin != null
            ? _buildPinScreen(_selectedForPin!)
            : _buildListScreen(),
      ),
    );
  }

  // ── List screen ──────────────────────────────────────────────────────────

  Widget _buildListScreen() {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Color(0xFFE5E7EB)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Оберіть фармацевта',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1C1C2E),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Пошук за прізвищем...',
                  hintStyle: const TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 13,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: Color(0xFF9CA3AF),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF4F5F8),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
        // List
        Expanded(
          child: _filtered.isEmpty
              ? const Center(
                  child: Text(
                    'Нікого не знайдено',
                    style:
                        TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: _filtered.length,
                  itemBuilder: (ctx, i) {
                    final p = _filtered[i];
                    return InkWell(
                      onTap: () => _selectForPin(p),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 11),
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                                color: Color(0xFFF3F4F6), width: 0.5),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8F3FB),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Text(
                                  p.user.isNotEmpty
                                      ? p.user[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    color: Color(0xFF1E7DC8),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                p.user,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF1C1C2E),
                                ),
                              ),
                            ),
                            const Icon(Icons.chevron_right,
                                size: 18, color: Color(0xFF9CA3AF)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        // Footer
        Container(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: Color(0xFFE5E7EB)),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                '${widget.pharmacists.length} фармацевтів',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF9CA3AF),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  'Скасувати',
                  style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── PIN screen ───────────────────────────────────────────────────────────

  Widget _buildPinScreen(PharmacistInfo p) {
    return Column(
      children: [
        // Header with back button
        Container(
          padding: const EdgeInsets.fromLTRB(12, 18, 20, 14),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Color(0xFFE5E7EB)),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: _isLoggingIn ? null : _backToList,
                icon: const Icon(Icons.arrow_back_rounded, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  p.user,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1C1C2E),
                  ),
                ),
              ),
            ],
          ),
        ),
        // PIN input
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F3FB),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      p.user.isNotEmpty ? p.user[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: Color(0xFF1E7DC8),
                        fontWeight: FontWeight.w700,
                        fontSize: 22,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Введіть пароль',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1C1C2E),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: 200,
                  child: TextField(
                    controller: _pinController,
                    focusNode: _pinFocusNode,
                    obscureText: true,
                    textAlign: TextAlign.center,
                    enabled: !_isLoggingIn,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 6,
                    ),
                    onSubmitted: (_) => _verifyPin(),
                    decoration: InputDecoration(
                      hintText: '****',
                      hintStyle: TextStyle(
                        fontSize: 20,
                        color: Colors.grey.shade300,
                        letterSpacing: 6,
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF4F5F8),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: _pinError != null
                              ? const Color(0xFFEF4444)
                              : const Color(0xFFE5E7EB),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: _pinError != null
                              ? const Color(0xFFEF4444)
                              : const Color(0xFFE5E7EB),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: _pinError != null
                              ? const Color(0xFFEF4444)
                              : const Color(0xFF1E7DC8),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
                if (_pinError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _pinError!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFEF4444),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                if (_showForceLogout) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: 200,
                    height: 34,
                    child: OutlinedButton.icon(
                      onPressed: _isLoggingIn ? null : _cleanupAndRetry,
                      icon: const Icon(Icons.logout_rounded, size: 15),
                      label: const Text('Завершити сесію',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFD97706),
                        side: const BorderSide(color: Color(0xFFFBBF24)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: 200,
                  height: 38,
                  child: ElevatedButton(
                    onPressed: _isLoggingIn ? null : _verifyPin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E7DC8),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _isLoggingIn
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Увійти',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
