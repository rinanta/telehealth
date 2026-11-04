import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../data/models/midwife_model.dart';
import '../../../data/repositories/midwife_repository.dart';

class MidwifeDetailScreen extends ConsumerWidget {
  final String midwifeId;

  const MidwifeDetailScreen({super.key, required this.midwifeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final midwife = ref.watch(midwifeByIdProvider(midwifeId));

    return midwife.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Detail Bidan')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => Scaffold(
        appBar: AppBar(title: const Text('Detail Bidan')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Profil bidan tidak dapat dimuat.'),
              TextButton(
                onPressed: () => ref.invalidate(midwifeByIdProvider(midwifeId)),
                child: const Text('Coba lagi'),
              ),
            ],
          ),
        ),
      ),
      data: (item) => item == null
          ? Scaffold(
              appBar: AppBar(title: const Text('Detail Bidan')),
              body: const Center(child: Text('Data bidan tidak ditemukan.')),
            )
          : _buildProfile(context, item),
    );
  }

  Widget _buildProfile(BuildContext context, Midwife midwife) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Profil Lengkap Bidan'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Profil
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: AppColors.secondaryContainer,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.secondary, width: 2),
                    ),
                    child: const Icon(Icons.person, color: AppColors.secondary, size: 44),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    midwife.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    midwife.credentialLabel,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: AppColors.secondaryDark, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Kredensial & Izin Resmi
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Verifikasi & Kredensial Medis', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  if (midwife.strNumber != null && midwife.strNumber!.isNotEmpty)
                    _buildKredensialRow(Icons.verified, 'Nomor STR Bidan', midwife.strNumber!),
                  if (midwife.strNumber != null &&
                      midwife.strNumber!.isNotEmpty &&
                      midwife.hospitalAffiliation != null &&
                      midwife.hospitalAffiliation!.isNotEmpty)
                    const Divider(height: 18),
                  if (midwife.hospitalAffiliation != null &&
                      midwife.hospitalAffiliation!.isNotEmpty)
                    _buildKredensialRow(
                      Icons.local_hospital_outlined,
                      'Fasilitas Praktik',
                      midwife.hospitalAffiliation!,
                    ),
                  const Divider(height: 18),
                  _buildKredensialRow(Icons.timer_outlined, 'Durasi Konsultasi', '30 Menit Sesi Chat Intensif'),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Deskripsi & Pendekatan Klinis
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Tentang & Pendekatan Pelayanan', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  if (midwife.bio != null && midwife.bio!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      midwife.bio!,
                      style: const TextStyle(fontSize: 13, height: 1.6, color: AppColors.textSecondary),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 30),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SafeArea(
          child: Row(
            children: [
              if (midwife.price != null) ...[
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Biaya Konsultasi', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                    Text(
                      Formatters.toRupiah(midwife.price!),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primary),
                    ),
                  ],
                ),
                const SizedBox(width: 20),
              ],
              Expanded(
                child: AppButton(
                  label: 'Pilih Jadwal & Slot',
                  icon: Icons.calendar_month_rounded,
                  onPressed: () => context.push('/booking-form/${midwife.uid}'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKredensialRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.secondary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            ],
          ),
        ),
      ],
    );
  }
}
