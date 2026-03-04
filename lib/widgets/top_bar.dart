import 'package:flutter/material.dart';

/// Top application bar with logo and pharmacist badge.
class TopBar extends StatelessWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1),
        ),
      ),
      child: Row(
        children: [
          // АНЦ Каса — logo image from asset
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              'assets/images/Logo1.png',
              height: 40,
              fit: BoxFit.contain,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F3FB),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: const Color(0xFF1E7DC8).withValues(alpha: 0.25)),
            ),
            child: const Row(
              children: [
                Icon(Icons.person_outline_rounded,
                    color: Color(0xFF1E7DC8), size: 15),
                SizedBox(width: 5),
                Text('Касир: Микола',
                    style:
                        TextStyle(color: Color(0xFF1E7DC8), fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
