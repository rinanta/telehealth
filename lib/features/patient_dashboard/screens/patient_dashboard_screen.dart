import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/booking_repository.dart';

class PatientDashboardScreen extends ConsumerWidget {
  const PatientDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider);
    final bookings = ref.watch(bookingsListProvider);

    // Ambil sesi booking pasien yang sedang aktif atau perlu perhatian
    final patientBookings = user == null
        ? <dynamic>[]
        : bookings.where((b) => b.patientId == user.uid).toList();
    final activeOrPendingBooking = patientBookings.cast<dynamic>().firstWhere(
      (b) =>
          b.status == 'active' ||
          b.status == 'confirmed' ||
          b.status == 'paid_pending_midwife' ||
          b.status == 'awaiting_payment',
      orElse: () => null,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.favorite,
                color: AppColors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'TeleBunda AI',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    user?.name ?? 'Pasien',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Keluar Akun',
            icon: const Icon(Icons.logout, color: AppColors.danger),
            onPressed: () async {
              await ref.read(authStateProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero Banner Chat AI (UI-04 CTA Utama)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, Color(0xFFE879F9)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              color: Colors.white,
                              size: 14,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Gemini AI Edukasi 24/7 Gratis',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Punya Pertanyaan Seputar Kehamilan?',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Dapatkan informasi seputar nutrisi, gerakan janin, dan tips kehamilan sehat secara instan.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => context.push('/ai-chat'),
                    icon: const Icon(
                      Icons.chat_bubble_rounded,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    label: const Text(
                      'Mulai Tanya AI Sekarang',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primary,
                      elevation: 0,
                      minimumSize: const Size(0, 42),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Sesi Konsultasi Aktif / Terjadwal (Jika Ada)
            if (activeOrPendingBooking != null) ...[
              const Text(
                'Sesi Konsultasi Terdekat',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: activeOrPendingBooking.status == 'active'
                        ? AppColors.success
                        : AppColors.border,
                    width: activeOrPendingBooking.status == 'active'
                        ? 1.8
                        : 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            activeOrPendingBooking.midwifeName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        StatusBadge(status: activeOrPendingBooking.status),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.access_time_rounded,
                          size: 14,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          Formatters.formatDateTime(
                            activeOrPendingBooking.slotStartAt,
                          ),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (activeOrPendingBooking.status == 'active')
                      AppButton(
                        label: 'Masuk Ruang Chat Sekarang (Aktif)',
                        icon: Icons.chat_rounded,
                        backgroundColor: AppColors.success,
                        onPressed: () => context.push(
                          '/consultation-chat/${activeOrPendingBooking.id}',
                        ),
                      )
                    else if (activeOrPendingBooking.status ==
                        'awaiting_payment')
                      AppButton(
                        label: 'Lanjutkan Pembayaran Midtrans Sandbox',
                        icon: Icons.payment_rounded,
                        backgroundColor: AppColors.paymentAccent,
                        onPressed: () => context.push(
                          '/payment-checkout/${activeOrPendingBooking.id}',
                        ),
                      )
                    else
                      AppButton(
                        label: 'Lihat Detail Status Booking',
                        isOutlined: true,
                        onPressed: () => context.push(
                          '/booking-status/${activeOrPendingBooking.id}',
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Menu Pintasan & Cari Bidan
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Konsultasi Bidan Terpercaya',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                TextButton(
                  onPressed: () => context.push('/midwife-catalog'),
                  child: const Text(
                    'Lihat Semua',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Card Cari Bidan (CTA Bidan)
            InkWell(
              onTap: () => context.push('/midwife-catalog'),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: AppColors.secondaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.medical_services_outlined,
                        color: AppColors.secondary,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Jadwalkan Konsultasi Chat Bidan',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Sesi chat intensif 30 menit, rekap hasil bidan & evaluasi keluhan.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Riwayat Terakhir
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Riwayat Konsultasi Selesai',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                TextButton(
                  onPressed: () => context.push('/patient-history'),
                  child: const Text(
                    'Semua Riwayat',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Card Riwayat Terakhir
            InkWell(
              onTap: () =>
                  context.push('/consultation-result/book_history_001'),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.description_outlined,
                        color: AppColors.textPrimary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hasil: Bdn. Siti Rahmawati',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Pusing ortostatik & kram ligamen',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    const StatusBadge(status: 'completed'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
