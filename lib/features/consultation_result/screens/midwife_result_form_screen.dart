import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_button.dart';
import '../../../data/models/booking_model.dart';
import '../../../data/repositories/booking_repository.dart';
import '../../../data/repositories/consultation_chat_repository.dart';

class MidwifeResultFormScreen extends ConsumerStatefulWidget {
  final String bookingId;

  const MidwifeResultFormScreen({super.key, required this.bookingId});

  @override
  ConsumerState<MidwifeResultFormScreen> createState() => _MidwifeResultFormScreenState();
}

class _MidwifeResultFormScreenState extends ConsumerState<MidwifeResultFormScreen> {
  final _summaryController = TextEditingController();
  final _adviceController = TextEditingController();
  final _supplementController = TextEditingController();
  final _followUpController = TextEditingController();

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
    final summary = _summaryController.text.trim();
    final advice = _adviceController.text.trim();
    final followUp = _followUpController.text.trim();

    if (summary.length < 10 || advice.length < 10 || followUp.length < 5) {
      setState(
        () => _errorMessage =
            'Ringkasan dan saran minimal 10 karakter, tindak lanjut minimal 5 karakter.',
      );
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      // FR-12: Bidan menyimpan ringkasan dan menyelesaikan konsultasi -> status completed
      await ref
          .read(bookingRepositoryProvider)
          .completeMidwifeConsultation(
            bookingId: widget.bookingId,
            summary: summary,
            advice: advice,
            supplementNote: _supplementController.text.trim(),
            followUp: followUp,
          );

      ref.invalidate(midwifeBookingsProvider);
      ref.invalidate(consultationSessionProvider(widget.bookingId));
      ref.invalidate(consultationResultProvider(widget.bookingId));

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.success,
          content: Text('Hasil konsultasi berhasil disimpan & sesi ditutup!'),
        ),
      );

      // Arahkan ke tampilan hasil
      context.pushReplacement('/consultation-result/${widget.bookingId}');
    } on DioException catch (error) {
      if (!mounted) return;
      final response = error.response?.data;
      final code = response is Map ? response['code'] : null;
      setState(
        () => _errorMessage = switch (code) {
          'booking_not_actionable' =>
            'Sesi ini tidak lagi aktif sehingga tidak dapat diselesaikan. Muat ulang daftar booking.',
          'booking_not_found' => 'Booking tidak ditemukan.',
          _ when error.response?.statusCode == 422 =>
            'Isian belum memenuhi syarat. Periksa kembali setiap kolom.',
          _ => 'Gagal menyimpan hasil konsultasi. Periksa koneksi lalu coba lagi.',
        },
      );
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _errorMessage =
            'Gagal menyimpan hasil konsultasi. Periksa koneksi lalu coba lagi.',
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookings = ref.watch(midwifeBookingsProvider).value ?? const <Booking>[];
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
                        Text('Pasien: ${booking?.patientName ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
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
