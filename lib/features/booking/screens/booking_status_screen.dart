import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../data/models/booking_model.dart';
import '../../../data/repositories/booking_repository.dart';

class BookingStatusScreen extends ConsumerWidget {
  final String bookingId;

  const BookingStatusScreen({super.key, required this.bookingId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookings = ref.watch(bookingsListProvider);
    final booking = bookings.cast<Booking?>().firstWhere(
          (b) => b?.id == bookingId,
          orElse: () => null,
        );

    if (booking == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Status Reservasi')),
        body: const Center(child: Text('Reservasi tidak ditemukan.')),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Status & Jadwal Konsultasi'),
        actions: [
          IconButton(
            tooltip: 'Ke Beranda',
            icon: const Icon(Icons.home_outlined),
            onPressed: () => context.go('/patient-dashboard'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Header
            Container(
              padding: const EdgeInsets.all(18),
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
                      const Text('Status Reservasi Saat Ini', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      StatusBadge(status: booking.status),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    booking.midwifeName,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded, size: 14, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Text(
                        Formatters.formatDateTime(booking.slotStartAt),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Stepper Status Sesuai PRD State Machine
            const Text(
              'Alur Proses Reservasi',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  _buildStepItem(
                    title: '1. Pembuatan Reservasi & Hold Slot',
                    subtitle: 'Slot waktu berhasil ditahan sementara',
                    isDone: true,
                    isActive: false,
                  ),
                  _buildStepDivider(true),
                  _buildStepItem(
                    title: '2. Pembayaran Mayar Sandbox',
                    subtitle: booking.isAwaitingPayment ? 'Menunggu pembayaran di sandbox gateway' : 'Pembayaran terverifikasi server',
                    isDone: !booking.isAwaitingPayment,
                    isActive: booking.isAwaitingPayment,
                  ),
                  _buildStepDivider(!booking.isAwaitingPayment),
                  _buildStepItem(
                    title: '3. Konfirmasi dari Bidan',
                    subtitle: booking.isPaidPendingMidwife
                        ? 'Menunggu Bidan menerima jadwal reservasi'
                        : (booking.isConfirmed || booking.isActive || booking.isCompleted)
                            ? 'Bidan telah mengonfirmasi kehadiran'
                            : 'Menunggu konfirmasi',
                    isDone: booking.isConfirmed || booking.isActive || booking.isCompleted,
                    isActive: booking.isPaidPendingMidwife,
                  ),
                  _buildStepDivider(booking.isConfirmed || booking.isActive || booking.isCompleted),
                  _buildStepItem(
                    title: '4. Sesi Konsultasi Chat (30 Menit)',
                    subtitle: booking.isActive
                        ? 'Sesi sedang berlangsung! Silakan masuk ruang chat.'
                        : booking.isCompleted
                            ? 'Sesi 30 menit selesai'
                            : 'Tombol chat akan dibuka saat sesi dimulai',
                    isDone: booking.isCompleted,
                    isActive: booking.isActive,
                  ),
                  _buildStepDivider(booking.isCompleted),
                  _buildStepItem(
                    title: '5. Rekap Hasil Konsultasi Medis',
                    subtitle: booking.isCompleted ? 'Hasil pemeriksaan dan saran bidan telah siap' : 'Disusun oleh bidan setelah sesi selesai',
                    isDone: booking.isCompleted,
                    isActive: false,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Aksi Sesuai Status
            if (booking.isActive)
              AppButton(
                label: 'Masuk ke Ruang Chat Konsultasi Sekarang',
                icon: Icons.chat_rounded,
                backgroundColor: AppColors.success,
                onPressed: () => context.push('/consultation-chat/${booking.id}'),
              )
            else if (booking.isCompleted)
              AppButton(
                label: 'Lihat Hasil Konsultasi & Catatan Bidan',
                icon: Icons.description_outlined,
                onPressed: () => context.push('/consultation-result/${booking.id}'),
              )
            else if (booking.isAwaitingPayment)
              AppButton(
                label: 'Lanjutkan Pembayaran Sandbox',
                icon: Icons.payment,
                backgroundColor: AppColors.mayarBrand,
                onPressed: () => context.push('/mayar-checkout/${booking.id}'),
              )
            else if (booking.isConfirmed)
              Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.lock_clock, color: AppColors.secondary, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Jadwal terkonfirmasi. Chat akan aktif saat Bidan membuka sesi sesuai waktu konsultasi.',
                            style: TextStyle(fontSize: 12, color: AppColors.secondaryDark),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Shortcut demo untuk kemudahan penguji
                  AppButton(
                    label: 'Simulasi Bidan Mulai Sesi (Demo Tester)',
                    icon: Icons.play_arrow_rounded,
                    backgroundColor: AppColors.secondary,
                    onPressed: () async {
                      await ref.read(bookingsListProvider.notifier).startConsultation(booking.id);
                      if (context.mounted) {
                        context.push('/consultation-chat/${booking.id}');
                      }
                    },
                  ),
                ],
              )
            else if (booking.isPaidPendingMidwife)
              Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.infoContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.hourglass_top, color: AppColors.info, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Pembayaran Anda telah diterima. Menunggu Bidan mengonfirmasi jadwal.',
                            style: TextStyle(fontSize: 12, color: Color(0xFF1E3A8A)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Shortcut demo simulasi terima booking
                  AppButton(
                    label: 'Simulasi Bidan Terima Booking (Demo Tester)',
                    icon: Icons.thumb_up_alt_outlined,
                    backgroundColor: AppColors.info,
                    onPressed: () async {
                      await ref.read(bookingsListProvider.notifier).midwifeAccept(booking.id);
                    },
                  ),
                ],
              ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildStepItem({
    required String title,
    required String subtitle,
    required bool isDone,
    required bool isActive,
  }) {
    Color iconColor;
    IconData icon;

    if (isDone) {
      iconColor = AppColors.success;
      icon = Icons.check_circle_rounded;
    } else if (isActive) {
      iconColor = AppColors.primary;
      icon = Icons.radio_button_checked;
    } else {
      iconColor = AppColors.textMuted;
      icon = Icons.radio_button_unchecked;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: iconColor),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: (isDone || isActive) ? FontWeight.w700 : FontWeight.w500,
                  color: (isDone || isActive) ? AppColors.textPrimary : AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStepDivider(bool isDone) {
    return Container(
      margin: const EdgeInsets.only(left: 9, top: 4, bottom: 4),
      height: 18,
      width: 2,
      color: isDone ? AppColors.success : AppColors.border,
    );
  }
}
