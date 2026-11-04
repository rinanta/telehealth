import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';

class ConsultationTimerBanner extends StatefulWidget {
  final DateTime startedAt;
  final DateTime? endsAt;
  final int durationMinutes;
  final VoidCallback? onTimerExpired;

  const ConsultationTimerBanner({
    super.key,
    required this.startedAt,
    this.endsAt,
    this.durationMinutes = 30,
    this.onTimerExpired,
  });

  @override
  State<ConsultationTimerBanner> createState() => _ConsultationTimerBannerState();
}

class _ConsultationTimerBannerState extends State<ConsultationTimerBanner> {
  late Timer _timer;
  int _secondsRemaining = 0;
  bool _expiredNotified = false;

  @override
  void initState() {
    super.initState();
    final endsAt = widget.endsAt ??
        widget.startedAt.add(Duration(minutes: widget.durationMinutes));
    final diff = endsAt.difference(DateTime.now()).inSeconds;
    _secondsRemaining = diff > 0 ? diff : 0;

    if (diff <= 0) {
      _expiredNotified = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onTimerExpired?.call();
      });
    }

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _calculateRemaining();
    });
  }

  void _calculateRemaining() {
    final endsAt = widget.endsAt ??
        widget.startedAt.add(Duration(minutes: widget.durationMinutes));
    final now = DateTime.now();
    final diff = endsAt.difference(now).inSeconds;

    if (mounted) {
      setState(() {
        _secondsRemaining = diff > 0 ? diff : 0;
      });
    }

    if (diff <= 0 && !_expiredNotified) {
      _expiredNotified = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onTimerExpired?.call();
      });
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWarning = _secondsRemaining <= 300 && _secondsRemaining > 0; // kurang dari 5 menit
    final isExpired = _secondsRemaining <= 0;

    Color bg;
    Color fg;
    String statusText;

    if (isExpired) {
      bg = AppColors.dangerContainer;
      fg = AppColors.danger;
      statusText = 'Waktu Konsultasi Telah Berakhir (30 Menit)';
    } else if (isWarning) {
      bg = AppColors.warningContainer;
      fg = const Color(0xFFB45309);
      statusText = 'Sisa Waktu < 5 Menit: Persiapkan Kesimpulan Sesi';
    } else {
      bg = AppColors.secondaryContainer;
      fg = AppColors.secondaryDark;
      statusText = 'Sesi Konsultasi Aktif (30 Menit)';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          bottom: BorderSide(
            color: fg.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Icon(
                  isExpired ? Icons.timer_off_rounded : Icons.timer_outlined,
                  size: 18,
                  color: fg,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    statusText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: fg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              Formatters.formatTimer(_secondsRemaining),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
