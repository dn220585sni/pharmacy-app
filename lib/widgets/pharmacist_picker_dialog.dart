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
  List<PharmacistInfo> _filtered = [];

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

  @override
  void dispose() {
    _searchController.dispose();
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
        child: Column(
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
                          onTap: () => Navigator.of(context).pop(p),
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
        ),
      ),
    );
  }
}
