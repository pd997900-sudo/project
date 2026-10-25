import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class SeverityBadge extends StatelessWidget {
  final String severity;

  const SeverityBadge({super.key, required this.severity});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    IconData icon;

    final s = severity.trim().toLowerCase();
    switch (s) {
      case 'emergency':
      case 'critical':
      case 'high':
        bg = const Color(0xFFFFEBEE);
        fg = AppTheme.emergencyRed;
        icon = Icons.warning_rounded;
        break;
      case 'medium':
      case 'moderate':
      case 'med':
      case 'amber':
      case 'yellow':
        bg = const Color(0xFFFFFDE7);
        fg = const Color(0xFFF57F17);
        icon = Icons.info_outline;
        break;
      case 'low':
      default:
        bg = const Color(0xFFE8F5E9);
        fg = AppTheme.successGreen;
        icon = Icons.check_circle_outline;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fg.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(
            severity.trim().toUpperCase(),
            style: TextStyle(
              color: fg,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  final String status;

  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;

    switch (status.toLowerCase()) {
      case 'submitted':
        bg = const Color(0xFFE3F2FD);
        fg = const Color(0xFF1976D2);
        break;
      case 'under verification':
      case 'verified':
        bg = const Color(0xFFEDE7F6);
        fg = const Color(0xFF512DA8);
        break;
      case 'accepted':
      case 'work started':
        bg = const Color(0xFFE0F7FA);
        fg = const Color(0xFF00838F);
        break;
      case 'repair in progress':
      case 'near completion':
        bg = const Color(0xFFFFF8E1);
        fg = const Color(0xFFFF8F00);
        break;
      case 'completed':
        bg = const Color(0xFFE8F5E9);
        fg = const Color(0xFF2E7D32);
        break;
      case 'rejected':
        bg = const Color(0xFFFFEBEE);
        fg = const Color(0xFFC62828);
        break;
      default:
        bg = const Color(0xFFF5F5F5);
        fg = const Color(0xFF616161);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: fg,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
