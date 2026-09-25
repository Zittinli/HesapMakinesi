import 'package:flutter/material.dart';

class UnreadDivider extends StatelessWidget {
  const UnreadDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 18),
      child: Row(
        children: [
          const Expanded(
            child: Divider(color: Color(0xFF3D4D5C), height: 1, thickness: 1),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              'Okunmamış',
              style: TextStyle(
                color: Colors.blueGrey.shade200,
                fontSize: 11,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const Expanded(
            child: Divider(color: Color(0xFF3D4D5C), height: 1, thickness: 1),
          ),
        ],
      ),
    );
  }
}
