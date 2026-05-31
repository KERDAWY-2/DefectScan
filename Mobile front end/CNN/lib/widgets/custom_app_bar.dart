import 'package:flutter/material.dart';
import 'app_logo.dart';

/// Shared app bar with the brand logo on the **left** (start of the title), so
/// it never collides with the back button that lives in the `leading` slot on
/// pushed screens. `actions` stays free for real actions (logout, etc.).
class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;

  const CustomAppBar({super.key, required this.title, this.actions});

  @override
  Widget build(BuildContext context) {
    return AppBar(
      titleSpacing: 12,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppLogoBadge(size: 34, padding: 6),
          const SizedBox(width: 10),
          Flexible(
            child: Text(title, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      actions: actions,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
