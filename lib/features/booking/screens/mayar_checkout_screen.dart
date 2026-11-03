import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../data/repositories/booking_repository.dart';

class MayarCheckoutScreen extends ConsumerStatefulWidget {
  final String bookingId;

  const MayarCheckoutScreen({super.key, required this.bookingId});

  @override
  ConsumerState<MayarCheckoutScreen> createState() => _MayarCheckoutScreenState();
}

class _MayarCheckoutScreenState extends ConsumerState<MayarCheckoutScreen> {
  bool _isProcessing = false;
  String? _statusMessage;

  Future<void> _handleSimulateSuccess() async {
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Menghubungkan ke gateway Mayar Sandbox...';
    });

    await Future.delayed(const Duration(milliseconds: 600));

    setState(() {
      _statusMessage = 'Menerima callback & memverifikasi webhook signature di Laravel...';
    });

    try {
      // FR-07 & FR-08: Verifikasi server mengubah booking menjadi paid_pending_midwife
      await ref.read(bookingsListProvider.notifier).simulatePayment(widget.bookingId);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.success,
          content: Text('Pembayaran Mayar Sandbox Berhasil Diverifikasi! Status: Menunggu Konfirmasi Bidan.'),
        ),
      );

      // Arahkan ke UI-09 (Status Booking & Jadwal)
      context.pushReplacement('/booking-status/${widget.bookingId}');
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Gagal memproses pembayaran: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final booking = ref.watch(bookingsListProvider).firstWhere(
          (b) => b.id == widget.bookingId,
          orElse: () => ref.read(bookingRepositoryProvider).getBookingById(widget.bookingId)!,
        );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Checkout Mayar Sandbox'),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Banner Lingkungan Sandbox
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.developer_mode_rounded, color: AppColors.mayarBrand, size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mayar Sandbox Test Environment',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1E40AF)),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Lingkungan uji simulasi pembayaran. Tidak ada transaksi uang sungguhan.',
                          style: TextStyle(fontSize: 11, color: Color(0xFF1E3A8A)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Card Tagihan Pembayaran
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  const Text('Total Tagihan Konsultasi', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  Text(
                    Formatters.toRupiah(booking.amount),
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 12),
                  _buildRow('ID Reservasi', booking.id),
                  const SizedBox(height: 10),
                  _buildRow('Bidan Konsultan', booking.midwifeName),
                  const SizedBox(height: 10),
                  _buildRow('Jadwal Sesi', Formatters.formatDateTime(booking.slotStartAt)),
                  const SizedBox(height: 10),
                  _buildRow('Metode Uji', 'QRIS / VA Sandbox Mayar'),
                  const SizedBox(height: 10),
                  _buildRow('Status', booking.isAwaitingPayment ? 'Menunggu Pembayaran' : 'Terbayar'),
                ],
              ),
            ),

            const SizedBox(height: 24),

            if (_isProcessing) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2.8, color: AppColors.mayarBrand),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _statusMessage ?? 'Memproses transaksi...',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Tombol Simulasi Pembayaran Sandbox
            AppButton(
              label: 'Simulasi Bayar Sukses (Mayar Sandbox)',
              icon: Icons.check_circle_outline_rounded,
              isLoading: _isProcessing,
              backgroundColor: AppColors.mayarBrand,
              onPressed: _isProcessing ? null : _handleSimulateSuccess,
            ),
            const SizedBox(height: 12),
            AppButton(
              label: 'Batalkan / Kembali ke Dashboard',
              isOutlined: true,
              onPressed: _isProcessing ? null : () => context.go('/patient-dashboard'),
            ),

            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Catatan Arsitektur: Sesuai PRD Bagian 6 (FR-07), status paid hanya boleh diubah setelah verifikasi callback webhook dari backend Laravel untuk mencegah manipulasi status dari sisi client.',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          ),
        ),
      ],
    );
  }
}
