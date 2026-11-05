import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/midwife_model.dart';
import '../../../data/models/slot_model.dart';
import '../../../data/repositories/booking_repository.dart';
import '../../../data/repositories/midwife_repository.dart';
import '../utils/booking_error_message.dart';

class BookingFormScreen extends ConsumerStatefulWidget {
  final String midwifeId;

  const BookingFormScreen({super.key, required this.midwifeId});

  @override
  ConsumerState<BookingFormScreen> createState() => _BookingFormScreenState();
}

class _BookingFormScreenState extends ConsumerState<BookingFormScreen> {
  final _complaintController = TextEditingController();
  ConsultationSlot? _selectedSlot;
  bool _isSubmitting = false;
  String? _submissionError;

  @override
  void dispose() {
    _complaintController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final midwife = ref.watch(midwifeByIdProvider(widget.midwifeId));

    return midwife.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Reservasi Jadwal')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => Scaffold(
        appBar: AppBar(title: const Text('Reservasi Jadwal')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Profil bidan tidak dapat dimuat.'),
              TextButton(
                onPressed: () =>
                    ref.invalidate(midwifeByIdProvider(widget.midwifeId)),
                child: const Text('Coba lagi'),
              ),
            ],
          ),
        ),
      ),
      data: (item) {
        if (item == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Reservasi Jadwal')),
            body: const Center(child: Text('Bidan tidak ditemukan.')),
          );
        }

        final slots = ref.watch(availableSlotsProvider(widget.midwifeId));
        return slots.when(
          loading: () => Scaffold(
            appBar: AppBar(title: const Text('Reservasi Jadwal')),
            body: const Center(child: CircularProgressIndicator()),
          ),
          error: (error, stackTrace) => Scaffold(
            appBar: AppBar(title: const Text('Reservasi Jadwal')),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Jadwal bidan tidak dapat dimuat.'),
                  TextButton(
                    onPressed: () => ref.invalidate(
                      availableSlotsProvider(widget.midwifeId),
                    ),
                    child: const Text('Coba lagi'),
                  ),
                ],
              ),
            ),
          ),
          data: (items) => _buildBookingForm(context, item, items),
        );
      },
    );
  }

  Widget _buildBookingForm(
    BuildContext context,
    Midwife midwife,
    List<ConsultationSlot> slots,
  ) {
    if (!slots.any((slot) => slot.id == _selectedSlot?.id)) {
      _selectedSlot = slots.isEmpty ? null : slots.first;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Pilih Jadwal Konsultasi')),
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
                    child: const Icon(
                      Icons.person,
                      color: AppColors.secondary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          midwife.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          midwife.credentialLabel,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
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
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            if (slots.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    'Belum ada jadwal tersedia untuk bidan ini.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              )
            else
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primaryContainer
                            : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.border,
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
                                  isSelected
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_off,
                                  color: isSelected
                                      ? AppColors.primary
                                      : AppColors.textSecondary,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        Formatters.formatShortDate(
                                          slot.startAt,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: isSelected
                                              ? FontWeight.w700
                                              : FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                      Text(
                                        '${Formatters.formatTime(slot.startAt)} - ${Formatters.formatTime(slot.endAt)}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.primary.withValues(alpha: 0.15)
                                  : AppColors.surfaceVariant,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Slot Tersedia',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),

            const SizedBox(height: 24),
            const Text(
              'Keluhan singkat',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _complaintController,
              maxLength: 1000,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Jelaskan singkat hal yang ingin dikonsultasikan',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Slot ditahan selama 15 menit. Tarif final dan status booking mengikuti ketentuan aplikasi.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            if (_submissionError != null) ...[
              const SizedBox(height: 12),
              Text(
                _submissionError!,
                key: const Key('booking-submit-error'),
                style: const TextStyle(color: AppColors.danger),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                key: const Key('create-booking-button'),
                onPressed:
                    _isSubmitting ||
                        _selectedSlot == null ||
                        _complaintController.text.trim().isEmpty
                    ? null
                    : () => _submitBooking(_selectedSlot!),
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.lock_clock),
                label: Text(
                  _isSubmitting ? 'Memproses...' : 'Tahan Slot & Buat Booking',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitBooking(ConsultationSlot slot) async {
    setState(() {
      _isSubmitting = true;
      _submissionError = null;
    });

    try {
      final booking = await ref
          .read(bookingRepositoryProvider)
          .createBookingRequest(
            slot: slot,
            complaint: _complaintController.text.trim(),
          );
      if (!mounted) return;

      ref.invalidate(availableSlotsProvider(widget.midwifeId));
      context.push('/booking-status/${booking.id}', extra: booking);
    } on DioException catch (error) {
      if (!mounted) return;
      final response = error.response?.data;
      final code = response is Map ? response['code'] : null;
      setState(() {
        _submissionError = switch (code) {
          'booking_configuration_unavailable' =>
            'Tarif bidan belum tersedia. Booking belum dapat dibuat.',
          _ => bookingSubmissionErrorMessage(error),
        };
      });
    } on FormatException {
      if (!mounted) return;
      setState(() {
        _submissionError =
            'Booking belum dapat diproses. Silakan coba lagi.';
      });
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }
}
