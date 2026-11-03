import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_button.dart';
import '../../../data/models/booking_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/booking_repository.dart';

class MidwifeResultFormScreen extends ConsumerStatefulWidget {
  final String bookingId;

  const MidwifeResultFormScreen({super.key, required this.bookingId});

  @override
  ConsumerState<MidwifeResultFormScreen> createState() => _MidwifeResultFormScreenState();
}

class _MidwifeResultFormScreenState extends ConsumerState<MidwifeResultFormScreen> {
  final _summaryController = TextEditingController(
    text: 'Pasien trimester 2 mengalami kram ligamen fisiologis (round ligament pain) dan hipotensi ortostatik ringan saat perubahan posisi mendadak.',
  );
  final _adviceController = TextEditingController(
    text: 'Anjurkan relaksasi peregangan pinggul, hidrasi air putih minimal 2.5 liter per hari, dan istirahat berbaring miring ke kiri.',
  );
  final _supplementController = TextEditingController(
    text: 'Lanjutkan Tablet Tambah Darah (Fe) 1x1 malam hari dan Kalsium 500mg 1x1 pagi hari.',
  );
  final _followUpController = TextEditingController(
    text: 'Bila timbul tanda bahaya seperti perdarahan atau nyeri hebat, segera ke IGD terdekat. Kontrol ANC rutin 2 minggu lagi.',
  );

  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _summaryController.dispose();
    _adviceController.dispose();
    _supplementController.dispose();
    _followUpController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (_summaryController.text.trim().isEmpty ||
        _adviceController.text.trim().isEmpty ||
        _followUpController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Kolom ringkasan, saran, dan tindak lanjut wajib diisi.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final user = ref.read(authStateProvider);
      final midwifeName = user?.name ?? 'Bdn. Siti Rahmawati, S.Tr.Keb';

      // FR-12: Bidan menyimpan ringkasan dan menyelesaikan konsultasi -> status completed
      await ref.read(bookingsListProvider.notifier).completeConsultation(
            bookingId: widget.bookingId,
            summary: _summaryController.text.trim(),
            advice: _adviceController.text.trim(),
            supplementNote: _supplementController.text.trim(),
            followUp: _followUpController.text.trim(),
            savedBy: midwifeName,
          );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(backgroundColor: AppColors.success, content: Text('Hasil konsultasi berhasil disimpan & sesi ditutup!')),
      );

      // Arahkan ke tampilan hasil
      context.pushReplacement('/consultation-result/${widget.bookingId}');
    } catch (e) {
      setState(() => _errorMessage = 'Gagal menyimpan hasil konsultasi: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookings = ref.watch(bookingsListProvider);
    final booking = bookings.cast<Booking?>().firstWhere(
          (b) => b?.id == widget.bookingId,
          orElse: () => null,
        );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Form Hasil Konsultasi Bidan'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Pasien Info Banner
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person_pin, color: AppColors.secondary, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Pasien: ${booking?.patientName ?? 'Bunda Anisa'}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        Text('Keluhan: ${booking?.complaint ?? '-'}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Ringkasan Keluhan & Anamnesis
            const Text('Ringkasan Anamnesis & Temuan Klinis *', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 6),
            TextField(
              controller: _summaryController,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'Tuliskan hasil evaluasi kondisi ibu dan janin...'),
            ),

            const SizedBox(height: 18),

            // Saran Klinis Bidan
            const Text('Saran & Edukasi Perawatan Mandiri *', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 6),
            TextField(
              controller: _adviceController,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'Petunjuk pola istirahat, nutrisi, hidrasi, dll...'),
            ),

            const SizedBox(height: 18),

            // Suplemen / Vitamin Maternal (Opsional)
            const Text('Anjuran Suplemen / Vitamin Maternal (Opsional)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 6),
            TextField(
              controller: _supplementController,
              maxLines: 2,
              decoration: const InputDecoration(hintText: 'Contoh: Tablet Fe 1x1, Asam Folat 400mcg, Kalsium...'),
            ),

            const SizedBox(height: 18),

            // Tindak Lanjut & Rujukan
            const Text('Tindak Lanjut & Arahan Rujukan / Kontrol *', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 6),
            TextField(
              controller: _followUpController,
              maxLines: 2,
              decoration: const InputDecoration(hintText: 'Jadwal ANC berikutnya, atau anjuran segera ke IGD jika ada tanda bahaya...'),
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(_errorMessage!, style: const TextStyle(fontSize: 12, color: AppColors.danger)),
            ],

            const SizedBox(height: 26),

            AppButton(
              label: 'Simpan Lembar Hasil & Selesaikan Sesi',
              icon: Icons.check_circle_rounded,
              backgroundColor: AppColors.secondary,
              isLoading: _isSaving,
              onPressed: _handleSave,
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
