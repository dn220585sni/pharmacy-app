import 'package:flutter/material.dart';

/// Спитати, чи відкрити зміну, коли фіскальна дія впирається в закриту зміну.
///
/// Спільний для продажу й службових операцій каси: обидва шляхи йдуть у
/// ПРРО, а з закритою зміною ПРРО мовчки відкриває нову — без службового
/// внесення, тож у ній немає ранкового залишку (так сталося 08.09).
///
/// Не глуха відмова, а вибір: `true` — користувач обрав «Відкрити зміну»,
/// і викличний код після відкриття продовжує ту саму дію.
Future<bool> askToOpenShift(
  BuildContext context, {
  required String message,
}) async {
  final open = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      icon: const Icon(Icons.lock_clock_rounded,
          color: Color(0xFFB45309), size: 36),
      title: const Text('Зміну не відкрито',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content:
          Text(message, style: const TextStyle(fontSize: 13.5, height: 1.4)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Скасувати'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Відкрити зміну'),
        ),
      ],
    ),
  );
  return open == true;
}
