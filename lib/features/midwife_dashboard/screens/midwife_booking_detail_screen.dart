import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../data/models/booking_model.dart';
import '../../../data/repositories/booking_repository.dart';

class MidwifeBookingDetailScreen extends ConsumerStatefulWidget {
  final String bookingId;

  const MidwifeBookingDetailScreen({super.key, required this.bookingId});

  @override
  ConsumerState<MidwifeBookingDetailScreen> createState() => _MidwifeBookingDetailScreenState();
}

class _MidwifeBookingDetailScreenState extends ConsumerState<MidwifeBookingDetailScreen> {
  final _reasonController = TextEditingController(text: 'Sedang ada tindakan pertolongan persalinan darurat di fasilitas kesehatan.');
  bool _isProcessing = false;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _handleAccept() async {
    setState(() => _isProcessing = true);
    await ref.read(bookingsListProvider.notifier).midwifeAccept(widget.bookingId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(backgroundColor: AppColors.success, content: Text('Reservasi berhasil dikonfirmasi!')),
    );
    context.pop();
  }

  void _showRejectDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tolak Reservasi Konsultasi', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tuliskan alasan penolakan untuk disampaikan kepada pasien:', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 10),
            TextField(
              controller: _reasonController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Alasan penolakan...',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _isProcessing = true);
              await ref.read(bookingsListProvider.notifier).midwifeReject(
                    widget.bookingId,
                    _reasonController.text.trim(),
                  );
              if (mounted) context.pop();
            },
            child: const Text('Konfirmasi Tolak'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bookings = ref.watch(bookingsListProvider);
    final booking = bookings.cast<Booking?>().firstWhere(
          (b) => b?.id == widget.bookingId,
          orElse: () => null,
        );

    if (booking == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Detail Reservasi')),
        body: const Center(child: Text('Reservasi tidak ditemukan.')),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Rincian Reservasi Pasien'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                      Text('ID: ${booking.id}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      StatusBadge(status: booking.status),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(booking.patientName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.calendar_month_outlined, size: 14, color: AppColors.secondary),
                      const SizedBox(width: 6),
                      Text(Formatters.formatDateTime(booking.slotStartAt), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Keluhan Anamnesis Pasien
            Container(
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
                  const Text('Keluhan / Catatan Pasien', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(booking.complaint, style: const TextStyle(fontSize: 13, height: 1.5, color: AppColors.textPrimary)),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Info Pembayaran Sandbox
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
                  const Text('Verifikasi Pembayaran', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Nominal Konsultasi', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      Text(Formatters.toRupiah(booking.amount), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Metode', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      const Text('Mayar Sandbox Gateway', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.mayarBrand)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('ID Pembayaran Eksternal', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      Text(booking.paymentId ?? '-', style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            if (booking.isPaidPendingMidwife) ...[
              AppButton(
                label: 'Konfirmasi & Terima Reservasi',
                icon: Icons.check_circle_outline,
                backgroundColor: AppColors.secondary,
                isLoading: _isProcessing,
                onPressed: _handleAccept,
              ),
              const SizedBox(height: 12),
              AppButton(
                label: 'Tolak dengan Alasan Medis',
                isOutlined: true,
                textColor: AppColors.danger,
                backgroundColor: AppColors.danger,
                onPressed: _isProcessing ? null : _showRejectDialog,
              ),
            ] else if (booking.isConfirmed) ...[
              AppButton(
                label: 'Mulai Sesi Konsultasi Sekarang',
                icon: Icons.chat_rounded,
                backgroundColor: AppColors.secondary,
                onPressed: () async {
                  await ref.read(bookingsListProvider.notifier).startConsultation(booking.id);
                  if (!context.mounted) return;
                  context.push('/consultation-chat/${booking.id}');
                },
              ),
            ],

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
