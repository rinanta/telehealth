import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../data/models/slot_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/booking_repository.dart';
import '../../../data/repositories/midwife_repository.dart';

class BookingFormScreen extends ConsumerStatefulWidget {
  final String midwifeId;

  const BookingFormScreen({super.key, required this.midwifeId});

  @override
  ConsumerState<BookingFormScreen> createState() => _BookingFormScreenState();
}

class _BookingFormScreenState extends ConsumerState<BookingFormScreen> {
  final _complaintController = TextEditingController(
    text: 'Sering pusing ringan saat beranjak dari tempat tidur dan kram perut sesekali setelah aktivitas.',
  );
  ConsultationSlot? _selectedSlot;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _complaintController.dispose();
    super.dispose();
  }

  Future<void> _handleConfirmBooking() async {
    if (_selectedSlot == null) {
      setState(() => _errorMessage = 'Harap pilih salah satu jadwal slot waktu konsultasi.');
      return;
    }

    if (_complaintController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Harap tuliskan keluhan atau topik yang ingin dikonsultasikan.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final midwife = ref.read(midwifeRepositoryProvider).getMidwifeById(widget.midwifeId);
      final patient = ref.read(authStateProvider) ?? AuthRepository.demoPatient;

      if (midwife == null) throw Exception('Data bidan tidak valid');

      // FR-06: Buat booking + hold slot -> status awaiting_payment
      final booking = await ref.read(bookingsListProvider.notifier).createBooking(
            patient: patient,
            midwife: midwife,
            slot: _selectedSlot!,
            complaint: _complaintController.text.trim(),
          );

      if (!mounted) return;
      // Langsung diarahkan ke UI-08 (Checkout Mayar Sandbox)
      context.pushReplacement('/mayar-checkout/${booking.id}');
    } catch (e) {
      setState(() => _errorMessage = 'Gagal membuat reservasi: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final midwife = ref.watch(midwifeRepositoryProvider).getMidwifeById(widget.midwifeId);
    final slots = ref.watch(midwifeRepositoryProvider).getAvailableSlots(widget.midwifeId);

    if (midwife == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Reservasi Jadwal')),
        body: const Center(child: Text('Bidan tidak ditemukan.')),
      );
    }

    // Set default slot jika belum dipilih
    _selectedSlot ??= slots.first;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Pilih Jadwal Konsultasi'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Ringkasan Bidan
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.person, color: AppColors.secondary, size: 28),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(midwife.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        Text(midwife.credentialLabel, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 22),

            // Pilihan Slot Waktu (FR-05)
            const Text(
              'Pilih Slot Waktu Konsultasi (30 Menit)',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 10),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: slots.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final slot = slots[index];
                final isSelected = _selectedSlot?.id == slot.id;

                return InkWell(
                  onTap: () => setState(() => _selectedSlot = slot),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.primaryContainer : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? AppColors.primary : AppColors.border,
                        width: isSelected ? 1.8 : 1.0,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Icon(
                                isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                                color: isSelected ? AppColors.primary : AppColors.textSecondary,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      Formatters.formatShortDate(slot.startAt),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                    Text(
                                      '${Formatters.formatTime(slot.startAt)} - ${Formatters.formatTime(slot.endAt)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.primary.withValues(alpha: 0.15) : AppColors.surfaceVariant,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('Slot Tersedia', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 24),

            // Keluhan Singkat Ibu
            const Text(
              'Keluhan atau Hal yang Ingin Dikonsultasikan',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _complaintController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Tuliskan usia kehamilan dan gejala/keluhan yang Bunda rasakan...',
              ),
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(_errorMessage!, style: const TextStyle(fontSize: 12, color: AppColors.danger)),
            ],

            const SizedBox(height: 24),

            // Rincian Pembayaran
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Biaya Sesi Konsultasi (30 Menit)', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                      Text(Formatters.toRupiah(midwife.price), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Biaya Layanan Platform', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                      Text('Rp 0 (Subsidi MVP)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.success)),
                    ],
                  ),
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Pembayaran', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      Text(Formatters.toRupiah(midwife.price), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.primary)),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),
            AppButton(
              label: 'Konfirmasi & Lanjut ke Mayar Sandbox',
              icon: Icons.lock_outline_rounded,
              isLoading: _isLoading,
              onPressed: _handleConfirmBooking,
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
