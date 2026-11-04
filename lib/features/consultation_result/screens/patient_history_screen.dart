import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../data/repositories/booking_repository.dart';

class PatientHistoryScreen extends ConsumerWidget {
  const PatientHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(patientHistoryProvider);

    if (historyAsync.isLoading && !historyAsync.hasValue) {
      return Scaffold(
        appBar: AppBar(title: const Text('Riwayat Konsultasi')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (historyAsync.hasError && !historyAsync.hasValue) {
      return Scaffold(
        appBar: AppBar(title: const Text('Riwayat Konsultasi')),
        body: Center(
          child: OutlinedButton(
            onPressed: () => ref.invalidate(patientHistoryProvider),
            child: const Text('Gagal memuat. Coba lagi'),
          ),
        ),
      );
    }

    final patientBookings = historyAsync.value ?? const [];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Riwayat Konsultasi'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(patientHistoryProvider),
          ),
        ],
      ),
      body: patientBookings.isEmpty
          ? const Center(child: Text('Belum ada riwayat konsultasi.'))
          : RefreshIndicator(
              onRefresh: () => ref.refresh(patientHistoryProvider.future),
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: patientBookings.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final booking = patientBookings[index];
                return InkWell(
                  onTap: () {
                    if (booking.isCompleted) {
                      context.push('/consultation-result/${booking.id}');
                    } else if (booking.isActive) {
                      context.push('/consultation-chat/${booking.id}');
                    } else {
                      context.push('/booking-status/${booking.id}');
                    }
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(booking.midwifeName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                            StatusBadge(status: booking.status),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.access_time_rounded, size: 14, color: AppColors.textSecondary),
                            const SizedBox(width: 4),
                            Text(Formatters.formatDateTime(booking.slotStartAt), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Keluhan: ${booking.complaint}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                        ),
                      ],
                    ),
                  ),
                );
              },
              ),
            ),
    );
  }
}
