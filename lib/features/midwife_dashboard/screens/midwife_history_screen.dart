import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../data/repositories/booking_repository.dart';

class MidwifeHistoryScreen extends ConsumerWidget {
  const MidwifeHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingsAsync = ref.watch(midwifeBookingsProvider);
    if (bookingsAsync.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (bookingsAsync.hasError) {
      return Scaffold(
        appBar: AppBar(title: const Text('Riwayat Pasien Praktik')),
        body: Center(
          child: OutlinedButton(
            onPressed: () => ref.invalidate(midwifeBookingsProvider),
            child: const Text('Gagal memuat. Coba lagi'),
          ),
        ),
      );
    }

    final midwifeBookings = bookingsAsync.value ?? [];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Riwayat Pasien Praktik')),
      body: midwifeBookings.isEmpty
          ? const Center(child: Text('Belum ada riwayat konsultasi pasien.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: midwifeBookings.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final booking = midwifeBookings[index];
                return InkWell(
                  onTap: () {
                    if (booking.isCompleted) {
                      context.push('/consultation-result/${booking.id}');
                    } else if (booking.isActive) {
                      context.push('/consultation-chat/${booking.id}');
                    } else {
                      context.push('/midwife-booking-detail/${booking.id}');
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
                            Text(
                              booking.patientName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            StatusBadge(status: booking.status),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(
                              Icons.access_time_rounded,
                              size: 14,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              Formatters.formatDateTime(booking.slotStartAt),
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Keluhan: ${booking.complaint}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              booking.isCompleted
                                  ? 'Lihat Lembar Hasil >'
                                  : 'Buka Detail >',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.secondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
