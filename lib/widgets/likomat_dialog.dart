import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ═════════════════════════════════════════════════════════════════════════════
// LIKOMAT DIALOG — cell selection for medicine vending machine (лікомат).
// Visual grid matches the physical locker layout: small cells on top,
// progressively larger towards the bottom.
// ═════════════════════════════════════════════════════════════════════════════

/// Status of a single likomat cell.
enum LikomatCellStatus {
  available, // empty, can be used
  occupied, // already has an order inside
  disabled, // out of service / maintenance
}

/// Size category for a cell (matches physical locker compartment).
enum LikomatCellSize { s, m, l, xl }

/// Model for a single likomat cell.
class LikomatCell {
  final int number;
  final LikomatCellSize size;
  final LikomatCellStatus status;
  final String? orderNumber; // set when occupied

  const LikomatCell({
    required this.number,
    required this.size,
    this.status = LikomatCellStatus.available,
    this.orderNumber,
  });
}

/// Row definition — how many cells + cell height for that row.
class _LikomatRow {
  final List<LikomatCell> cells;
  final double height;

  const _LikomatRow({required this.cells, required this.height});
}

// ── Mock data: 52 cells arranged like a real лікомат ─────────────────────────
// Row 1-2: 10 small cells each   (1–20)
// Row 3-4:  8 medium cells each  (21–36)
// Row 5-6:  6 large cells each   (37–48)
// Row 7:    4 extra-large cells   (49–52)
// Total: 10+10+8+8+6+6+4 = 52

final List<_LikomatRow> _likomatGrid = [
  // ── Row 1: small (1–10) ───────────────────────────────────
  _LikomatRow(height: 42, cells: const [
    LikomatCell(number: 1,  size: LikomatCellSize.s, status: LikomatCellStatus.occupied, orderNumber: '1422'),
    LikomatCell(number: 2,  size: LikomatCellSize.s),
    LikomatCell(number: 3,  size: LikomatCellSize.s, status: LikomatCellStatus.occupied, orderNumber: '0264'),
    LikomatCell(number: 4,  size: LikomatCellSize.s),
    LikomatCell(number: 5,  size: LikomatCellSize.s, status: LikomatCellStatus.occupied, orderNumber: '2456'),
    LikomatCell(number: 6,  size: LikomatCellSize.s),
    LikomatCell(number: 7,  size: LikomatCellSize.s, status: LikomatCellStatus.disabled),
    LikomatCell(number: 8,  size: LikomatCellSize.s),
    LikomatCell(number: 9,  size: LikomatCellSize.s),
    LikomatCell(number: 10, size: LikomatCellSize.s, status: LikomatCellStatus.occupied, orderNumber: '3891'),
  ]),
  // ── Row 2: small (11–20) ──────────────────────────────────
  _LikomatRow(height: 42, cells: const [
    LikomatCell(number: 11, size: LikomatCellSize.s),
    LikomatCell(number: 12, size: LikomatCellSize.s, status: LikomatCellStatus.occupied, orderNumber: '1645'),
    LikomatCell(number: 13, size: LikomatCellSize.s),
    LikomatCell(number: 14, size: LikomatCellSize.s),
    LikomatCell(number: 15, size: LikomatCellSize.s, status: LikomatCellStatus.occupied, orderNumber: '0937'),
    LikomatCell(number: 16, size: LikomatCellSize.s),
    LikomatCell(number: 17, size: LikomatCellSize.s, status: LikomatCellStatus.occupied, orderNumber: '4210'),
    LikomatCell(number: 18, size: LikomatCellSize.s),
    LikomatCell(number: 19, size: LikomatCellSize.s),
    LikomatCell(number: 20, size: LikomatCellSize.s, status: LikomatCellStatus.disabled),
  ]),
  // ── Row 3: medium (21–28) ─────────────────────────────────
  _LikomatRow(height: 52, cells: const [
    LikomatCell(number: 21, size: LikomatCellSize.m),
    LikomatCell(number: 22, size: LikomatCellSize.m, status: LikomatCellStatus.occupied, orderNumber: '5678'),
    LikomatCell(number: 23, size: LikomatCellSize.m),
    LikomatCell(number: 24, size: LikomatCellSize.m),
    LikomatCell(number: 25, size: LikomatCellSize.m),
    LikomatCell(number: 26, size: LikomatCellSize.m),
    LikomatCell(number: 27, size: LikomatCellSize.m, status: LikomatCellStatus.occupied, orderNumber: '7823'),
    LikomatCell(number: 28, size: LikomatCellSize.m),
  ]),
  // ── Row 4: medium (29–36) ─────────────────────────────────
  _LikomatRow(height: 52, cells: const [
    LikomatCell(number: 29, size: LikomatCellSize.m),
    LikomatCell(number: 30, size: LikomatCellSize.m, status: LikomatCellStatus.disabled),
    LikomatCell(number: 31, size: LikomatCellSize.m, status: LikomatCellStatus.occupied, orderNumber: '9012'),
    LikomatCell(number: 32, size: LikomatCellSize.m, status: LikomatCellStatus.occupied, orderNumber: '3456'),
    LikomatCell(number: 33, size: LikomatCellSize.m),
    LikomatCell(number: 34, size: LikomatCellSize.m),
    LikomatCell(number: 35, size: LikomatCellSize.m),
    LikomatCell(number: 36, size: LikomatCellSize.m, status: LikomatCellStatus.occupied, orderNumber: '6789'),
  ]),
  // ── Row 5: large (37–42) ──────────────────────────────────
  _LikomatRow(height: 64, cells: const [
    LikomatCell(number: 37, size: LikomatCellSize.l),
    LikomatCell(number: 38, size: LikomatCellSize.l),
    LikomatCell(number: 39, size: LikomatCellSize.l, status: LikomatCellStatus.occupied, orderNumber: '2345'),
    LikomatCell(number: 40, size: LikomatCellSize.l),
    LikomatCell(number: 41, size: LikomatCellSize.l),
    LikomatCell(number: 42, size: LikomatCellSize.l, status: LikomatCellStatus.occupied, orderNumber: '8901'),
  ]),
  // ── Row 6: large (43–48) ──────────────────────────────────
  _LikomatRow(height: 64, cells: const [
    LikomatCell(number: 43, size: LikomatCellSize.l),
    LikomatCell(number: 44, size: LikomatCellSize.l),
    LikomatCell(number: 45, size: LikomatCellSize.l),
    LikomatCell(number: 46, size: LikomatCellSize.l, status: LikomatCellStatus.disabled),
    LikomatCell(number: 47, size: LikomatCellSize.l),
    LikomatCell(number: 48, size: LikomatCellSize.l),
  ]),
  // ── Row 7: extra-large (49–52) ────────────────────────────
  _LikomatRow(height: 78, cells: const [
    LikomatCell(number: 49, size: LikomatCellSize.xl),
    LikomatCell(number: 50, size: LikomatCellSize.xl, status: LikomatCellStatus.occupied, orderNumber: '4567'),
    LikomatCell(number: 51, size: LikomatCellSize.xl, status: LikomatCellStatus.occupied, orderNumber: '7890'),
    LikomatCell(number: 52, size: LikomatCellSize.xl),
  ]),
];

// Flat list of all cells for lookup
List<LikomatCell> get _allCells =>
    _likomatGrid.expand((r) => r.cells).toList();

// ═════════════════════════════════════════════════════════════════════════════

/// Shows the likomat cell selection dialog.
/// Returns the selected cell number, or null if cancelled.
Future<int?> showLikomatDialog(BuildContext context) {
  return showDialog<int>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const _LikomatDialogContent(),
  );
}

class _LikomatDialogContent extends StatefulWidget {
  const _LikomatDialogContent();

  @override
  State<_LikomatDialogContent> createState() => _LikomatDialogContentState();
}

class _LikomatDialogContentState extends State<_LikomatDialogContent> {
  final _cellInputController = TextEditingController();
  final _cellInputFocus = FocusNode();
  int? _selectedCell;
  String? _errorMessage;

  List<LikomatCell> get _cells => _allCells;

  int get _availableCount =>
      _cells.where((c) => c.status == LikomatCellStatus.available).length;

  int get _occupiedCount =>
      _cells.where((c) => c.status == LikomatCellStatus.occupied).length;

  @override
  void initState() {
    super.initState();
    _cellInputController.addListener(_onInputChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cellInputFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _cellInputController.dispose();
    _cellInputFocus.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    final text = _cellInputController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _selectedCell = null;
        _errorMessage = null;
      });
      return;
    }

    final num = int.tryParse(text);
    if (num == null) {
      setState(() {
        _selectedCell = null;
        _errorMessage = 'Введіть число';
      });
      return;
    }

    final cell = _cells.cast<LikomatCell?>().firstWhere(
          (c) => c!.number == num,
          orElse: () => null,
        );

    if (cell == null) {
      setState(() {
        _selectedCell = null;
        _errorMessage = 'Комірка №$num не знайдена';
      });
    } else if (cell.status == LikomatCellStatus.occupied) {
      setState(() {
        _selectedCell = null;
        _errorMessage = 'Комірка №$num зайнята (зам. ${cell.orderNumber})';
      });
    } else if (cell.status == LikomatCellStatus.disabled) {
      setState(() {
        _selectedCell = null;
        _errorMessage = 'Комірка №$num не працює';
      });
    } else {
      setState(() {
        _selectedCell = num;
        _errorMessage = null;
      });
    }
  }

  void _selectCellFromGrid(LikomatCell cell) {
    if (cell.status != LikomatCellStatus.available) return;

    setState(() {
      if (_selectedCell == cell.number) {
        _selectedCell = null;
        _cellInputController.text = '';
      } else {
        _selectedCell = cell.number;
        _cellInputController.text = '${cell.number}';
        _errorMessage = null;
      }
    });
  }

  void _confirm() {
    if (_selectedCell == null) return;
    Navigator.of(context).pop(_selectedCell);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.of(context).pop();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.enter &&
              _selectedCell != null) {
            _confirm();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Container(
          width: 680,
          color: Colors.white,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(),
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              _buildInputSection(),
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              _buildGrid(),
              _buildLegend(),
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFF0F5FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.lock_outline_rounded,
                size: 20, color: Color(0xFF1E7DC8)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Лікомат — вибір комірки',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1C1C2E),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Вільних: $_availableCount  •  Зайнятих: $_occupiedCount  •  Всього: ${_cells.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(8),
              ),
              child:
                  const Icon(Icons.close, size: 16, color: Color(0xFF9CA3AF)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Input section ───────────────────────────────────────────────────────────

  Widget _buildInputSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: Row(
        children: [
          const Text(
            'Номер комірки:',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFF374151),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 100,
            height: 38,
            child: TextField(
              controller: _cellInputController,
              focusNode: _cellInputFocus,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: '—',
                hintStyle: TextStyle(
                  fontSize: 15,
                  color: Colors.grey.shade300,
                ),
                filled: true,
                fillColor: const Color(0xFFF9FAFB),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: _errorMessage != null
                        ? const Color(0xFFEF4444)
                        : const Color(0xFFE5E7EB),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: _errorMessage != null
                        ? const Color(0xFFEF4444)
                        : const Color(0xFFE5E7EB),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: _errorMessage != null
                        ? const Color(0xFFEF4444)
                        : const Color(0xFF1E7DC8),
                    width: 1.5,
                  ),
                ),
              ),
              onSubmitted: (_) {
                if (_selectedCell != null) _confirm();
              },
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 38,
            child: ElevatedButton.icon(
              onPressed: _selectedCell != null ? _confirm : null,
              icon: const Icon(Icons.lock_open_rounded, size: 16),
              label: const Text('Відкрити',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: const Color(0xFF16A34A),
                disabledForegroundColor: const Color(0xFFD1D5DB),
                disabledBackgroundColor: const Color(0xFFF4F5F8),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          ),
          if (_selectedCell != null) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF1E7DC8), width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle,
                      size: 14, color: Color(0xFF1E7DC8)),
                  const SizedBox(width: 6),
                  Text(
                    'Комірка №$_selectedCell',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E7DC8),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_errorMessage != null) ...[
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                _errorMessage!,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFFEF4444),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Grid ─────────────────────────────────────────────────────────────────────

  Widget _buildGrid() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Size label for top rows
            _buildSizeLabel('S', 'Маленькі'),
            const SizedBox(height: 4),
            _buildGridRow(_likomatGrid[0]),
            const SizedBox(height: 4),
            _buildGridRow(_likomatGrid[1]),
            const SizedBox(height: 8),
            // Size label for medium rows
            _buildSizeLabel('M', 'Середні'),
            const SizedBox(height: 4),
            _buildGridRow(_likomatGrid[2]),
            const SizedBox(height: 4),
            _buildGridRow(_likomatGrid[3]),
            const SizedBox(height: 8),
            // Size label for large rows
            _buildSizeLabel('L', 'Великі'),
            const SizedBox(height: 4),
            _buildGridRow(_likomatGrid[4]),
            const SizedBox(height: 4),
            _buildGridRow(_likomatGrid[5]),
            const SizedBox(height: 8),
            // Size label for extra-large row
            _buildSizeLabel('XL', 'Дуже великі'),
            const SizedBox(height: 4),
            _buildGridRow(_likomatGrid[6]),
          ],
        ),
      ),
    );
  }

  Widget _buildSizeLabel(String code, String label) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: const Color(0xFFE5E7EB),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            code,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: Color(0xFF6B7280),
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: Color(0xFF9CA3AF),
          ),
        ),
      ],
    );
  }

  Widget _buildGridRow(_LikomatRow row) {
    return Row(
      children: [
        for (var i = 0; i < row.cells.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(child: _buildCellTile(row.cells[i], row.height)),
        ],
      ],
    );
  }

  Widget _buildCellTile(LikomatCell cell, double height) {
    final isSelected = _selectedCell == cell.number;
    final isAvailable = cell.status == LikomatCellStatus.available;
    final isOccupied = cell.status == LikomatCellStatus.occupied;
    final isDisabled = cell.status == LikomatCellStatus.disabled;

    Color bgColor;
    Color borderColor;
    Color textColor;

    if (isSelected) {
      bgColor = const Color(0xFF1E7DC8);
      borderColor = const Color(0xFF1565A8);
      textColor = Colors.white;
    } else if (isAvailable) {
      bgColor = const Color(0xFFF0FDF4);
      borderColor = const Color(0xFF86EFAC);
      textColor = const Color(0xFF166534);
    } else if (isOccupied) {
      bgColor = const Color(0xFFFEF3C7);
      borderColor = const Color(0xFFFCD34D);
      textColor = const Color(0xFF92400E);
    } else {
      // disabled
      bgColor = const Color(0xFFF3F4F6);
      borderColor = const Color(0xFFE5E7EB);
      textColor = const Color(0xFFD1D5DB);
    }

    return GestureDetector(
      onTap: isAvailable ? () => _selectCellFromGrid(cell) : null,
      child: MouseRegion(
        cursor:
            isAvailable ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: height,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: borderColor,
              width: isSelected ? 2 : 1.5,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color(0xFF1E7DC8).withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Cell number
              Text(
                '${cell.number}',
                style: TextStyle(
                  fontSize: isSelected ? 15 : 13,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
              // Status indicator below number
              if (isOccupied && cell.orderNumber != null) ...[
                const SizedBox(height: 1),
                Text(
                  cell.orderNumber!,
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w500,
                    color: textColor.withValues(alpha: 0.7),
                  ),
                ),
              ] else if (isDisabled) ...[
                const SizedBox(height: 1),
                Icon(Icons.block, size: 11, color: textColor),
              ] else if (isSelected) ...[
                const SizedBox(height: 1),
                const Icon(Icons.check, size: 13, color: Colors.white),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Legend ───────────────────────────────────────────────────────────────────

  Widget _buildLegend() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _legendItem(
              const Color(0xFFF0FDF4), const Color(0xFF86EFAC), 'Вільна'),
          const SizedBox(width: 16),
          _legendItem(
              const Color(0xFFFEF3C7), const Color(0xFFFCD34D), 'Зайнята'),
          const SizedBox(width: 16),
          _legendItem(
              const Color(0xFFF3F4F6), const Color(0xFFE5E7EB), 'Не працює'),
          const SizedBox(width: 16),
          _legendItem(
              const Color(0xFF1E7DC8), const Color(0xFF1565A8), 'Обрана'),
        ],
      ),
    );
  }

  Widget _legendItem(Color bg, Color border, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: border, width: 1),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF6B7280),
          ),
        ),
      ],
    );
  }

  // ── Footer ──────────────────────────────────────────────────────────────────

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
      child: Row(
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF6B7280),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: const Text('Скасувати',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
          const Spacer(),
          if (_selectedCell != null)
            Text(
              'Enter — підтвердити',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade400,
              ),
            ),
          const SizedBox(width: 12),
          SizedBox(
            height: 40,
            child: ElevatedButton.icon(
              onPressed: _selectedCell != null ? _confirm : null,
              icon: const Icon(Icons.lock_open_rounded, size: 18),
              label: Text(
                _selectedCell != null
                    ? 'Відкрити комірку №$_selectedCell'
                    : 'Оберіть комірку',
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: const Color(0xFF16A34A),
                disabledForegroundColor: const Color(0xFFD1D5DB),
                disabledBackgroundColor: const Color(0xFFF4F5F8),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
