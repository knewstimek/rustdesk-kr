import 'package:flutter/material.dart';

import '../../models/android_vm_keyboard_input.dart';

class AndroidVmImeControls extends StatelessWidget {
  final AndroidVmImeKey selection;
  final VoidCallback onToggle;
  final ValueChanged<AndroidVmImeKey> onSelected;

  const AndroidVmImeControls({
    super.key,
    required this.selection,
    required this.onToggle,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          onPressed: onToggle,
          child: const Text('A/가', style: TextStyle(color: Colors.white)),
        ),
        PopupMenuButton<AndroidVmImeKey>(
          initialValue: selection,
          onSelected: onSelected,
          itemBuilder: (_) => [
            for (final choice in AndroidVmImeKey.values)
              CheckedPopupMenuItem(
                value: choice,
                checked: choice == selection,
                child: Text('${choice.label} · ${choice.shortcut}'),
              ),
          ],
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              '${selection.label} ▾',
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
        ),
      ],
    );
  }
}
