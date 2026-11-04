import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/booking_repository.dart';

class ConsultationResultScreen extends ConsumerWidget {
  final String bookingId;

  const ConsultationResultScreen({super.key, required this.bookingId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultAsync = ref.watch(consultationResultProvider(bookingId));
    final isMidwife = ref.watch(authStateProvider)?.isMidwife ?? false;

    if (resultAsync.isLoading && !resultAsync.hasValue) {
      return Scaffold(
        appBar: AppBar(title: const Text('Hasil Konsultasi')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (resultAsync.hasError && !resultAsync.hasValue) {
      return Scaffold(
        appBar: AppBar(title: const Text('Hasil Konsultasi')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Hasil konsultasi belum dapat dimuat. Periksa koneksi lalu coba lagi.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () =>
                      ref.invalidate(consultationResultProvider(bookingId)),
                  child: const Text('Muat ulang'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final result = resultAsync.value;
    final homeRoute = isMidwife ? '/midwife-dashboard' : '/patient-dashboard';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Lembar Hasil Konsultasi'),
        actions: [
          IconButton(
            tooltip: 'Lihat Arsip Chat',
            icon: const Icon(Icons.chat_outlined),
            onPressed: () => context.push('/consultation-chat/$bookingId'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Kartu Medis
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.secondaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.verified, size: 14, color: AppColors.secondary),
                              SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  'TeleBunda Medical Note',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.secondaryDark),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        result == null
                            ? '-'
                            : Formatters.formatShortDate(result.completedAt),
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('Pasien: ${result?.patientName ?? '-'}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('Bidan Pemeriksa: ${result?.midwifeName ?? '-'}', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                ],
              ),
            ),

            const SizedBox(height: 20),

            if (result == null)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.hourglass_empty_rounded, size: 40, color: AppColors.warning),
                    const SizedBox(height: 12),
                    const Text(
                      'Bidan sedang menyusun rekap lembar hasil konsultasi ini. Silakan periksa kembali beberapa saat lagi.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () =>
                          ref.invalidate(consultationResultProvider(bookingId)),
                      child: const Text('Muat ulang'),
                    ),
                  ],
                ),
              )
            else ...[
              // Bagian 1: Ringkasan Keluhan & Evaluasi
              _buildSectionCard(
                icon: Icons.assignment_outlined,
                title: 'Ringkasan Anamnesis & Evaluasi',
                content: result.summary,
              ),

              const SizedBox(height: 16),

              // Bagian 2: Saran Klinis Bidan
              _buildSectionCard(
                icon: Icons.lightbulb_outline_rounded,
                title: 'Saran & Petunjuk Perawatan',
                content: result.advice,
              ),

              const SizedBox(height: 16),

              // Bagian 3: Anjuran Suplemen Maternal
              if (result.supplementNote != null && result.supplementNote!.isNotEmpty) ...[
                _buildSectionCard(
                  icon: Icons.medication_outlined,
                  title: 'Anjuran Suplemen & Vitamin Maternal',
                  content: result.supplementNote!,
                  accentColor: AppColors.secondary,
                ),
                const SizedBox(height: 16),
              ],

              // Bagian 4: Tindak Lanjut & Rujukan
              _buildSectionCard(
                icon: Icons.alt_route_rounded,
                title: 'Tindak Lanjut & Jadwal Kontrol',
                content: result.followUp,
                accentColor: const Color(0xFFD97706),
              ),

              const SizedBox(height: 24),

              // Catatan Legal
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 16, color: AppColors.textSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Dicatat secara resmi oleh ${result.savedBy} pada ${Formatters.formatDateTime(result.completedAt)}.',
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 28),
            AppButton(
              label: 'Kembali ke Beranda',
              isOutlined: true,
              onPressed: () => context.go(homeRoute),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required IconData icon,
    required String title,
    required String content,
    Color accentColor = AppColors.primary,
  }) {
    return Container(
      width: double.infinity,
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
            children: [
              Icon(icon, size: 18, color: accentColor),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            content,
            style: const TextStyle(fontSize: 13, height: 1.55, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}
