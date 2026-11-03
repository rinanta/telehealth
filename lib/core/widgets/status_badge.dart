import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class StatusBadge extends StatelessWidget {
  final String status;

  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    String label;
    IconData icon;

    switch (status) {
      case 'awaiting_payment':
        bg = AppColors.warningContainer;
        fg = const Color(0xFFB45309);
        label = 'Menunggu Bayar';
        icon = Icons.hourglass_top_rounded;
        break;
      case 'paid_pending_midwife':
        bg = AppColors.infoContainer;
        fg = const Color(0xFF1D4ED8);
        label = 'Menunggu Bidan';
        icon = Icons.mark_email_unread_outlined;
        break;
      case 'confirmed':
        bg = AppColors.secondaryContainer;
        fg = AppColors.secondaryDark;
        label = 'Terkonfirmasi';
        icon = Icons.event_available_rounded;
        break;
      case 'active':
        bg = AppColors.successContainer;
        fg = const Color(0xFF047857);
        label = 'Sesi Aktif';
        icon = Icons.chat_bubble_rounded;
        break;
      case 'completed':
        bg = const Color(0xFFF1F5F9);
        fg = AppColors.textSecondary;
        label = 'Selesai';
        icon = Icons.check_circle_outline_rounded;
        break;
      case 'rejected':
        bg = AppColors.dangerContainer;
        fg = AppColors.danger;
        label = 'Ditolak';
        icon = Icons.cancel_outlined;
        break;
      default:
        bg = AppColors.surfaceVariant;
        fg = AppColors.textSecondary;
        label = status;
        icon = Icons.info_outline_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
