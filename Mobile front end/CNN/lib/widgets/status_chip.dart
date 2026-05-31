import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Color for a report lifecycle status. Shared so screens don't each redefine
/// their own `_statusColor`.
Color statusColor(String status) {
  switch (status) {
    case 'pending':
      return kStatusPending;
    case 'assigned':
      return kStatusAssigned;
    case 'fixer_done':
      return kStatusFixerDone;
    case 'completed':
      return kStatusCompleted;
    default:
      return kStatusPending;
  }
}

String statusLabel(String status) {
  switch (status) {
    case 'pending':
      return 'Pending';
    case 'assigned':
      return 'Assigned';
    case 'fixer_done':
      return 'Fixer done';
    case 'completed':
      return 'Completed';
    default:
      return status;
  }
}

/// A small colored pill showing a report's status.
class StatusChip extends StatelessWidget {
  final String status;
  const StatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final c = statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            statusLabel(status),
            style: TextStyle(
              color: c == kStatusAssigned ? kBrandAmberDark : c,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}
