import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../data/models/booking_hold_model.dart';
import '../../../data/repositories/booking_repository.dart';

class MayarCheckoutScreen extends ConsumerStatefulWidget {
  final String bookingId;

  const MayarCheckoutScreen({super.key, required this.bookingId});

  @override
  ConsumerState<MayarCheckoutScreen> createState() =>
      _MayarCheckoutScreenState();
}

class _MayarCheckoutScreenState extends ConsumerState<MayarCheckoutScreen> {
  final _mobileController = TextEditingController();
  Timer? _timer;
  DateTime _now = DateTime.now();
  bool _isProcessing = false;
  String? _checkoutUrl;
  String? _errorMessage;
  String? _infoMessage;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _mobileController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bookingAsync = ref.watch(serverBookingProvider(widget.bookingId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Pembayaran Mayar Sandbox')),
      body: bookingAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _buildLoadError(),
        data: _buildCheckout,
      ),
    );
  }

  Widget _buildCheckout(BookingHold booking) {
    final paymentUrl = _checkoutUrl ?? booking.checkoutUrl;
    final remaining = booking.holdExpiresAt.difference(_now);
    final holdExpired = remaining <= Duration.zero;
    final isAwaitingPayment = booking.status == 'awaiting_payment';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: const Text(
              'Pembayaran diproses melalui halaman resmi Mayar. Status booking hanya berubah setelah server memverifikasi pembayaran.',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF1E3A8A),
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                const Text(
                  'Total Tagihan Konsultasi',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  Formatters.toRupiah(booking.amount),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),
                _buildRow('ID Reservasi', booking.id),
                const SizedBox(height: 10),
                _buildRow(
                  'Jadwal Sesi',
                  Formatters.formatDateTime(booking.slotStartAt),
                ),
                const SizedBox(height: 10),
                _buildRow(
                  'Status',
                  isAwaitingPayment ? 'Menunggu Pembayaran' : booking.status,
                ),
                if (isAwaitingPayment) ...[
                  const SizedBox(height: 10),
                  _buildRow(
                    'Sisa waktu hold',
                    holdExpired
                        ? 'Kedaluwarsa'
                        : '${remaining.inMinutes.toString().padLeft(2, '0')}:${(remaining.inSeconds % 60).toString().padLeft(2, '0')}',
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (isAwaitingPayment && !holdExpired && paymentUrl == null) ...[
            TextField(
              controller: _mobileController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Nomor ponsel',
                hintText: 'Contoh: 081234567890',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_errorMessage != null)
            _buildMessage(_errorMessage!, isError: true),
          if (_infoMessage != null) _buildMessage(_infoMessage!),
          if (isAwaitingPayment && !holdExpired)
            AppButton(
              label: paymentUrl == null
                  ? 'Buat tautan pembayaran'
                  : 'Lanjutkan ke pembayaran',
              icon: Icons.payment,
              backgroundColor: AppColors.mayarBrand,
              isLoading: _isProcessing,
              onPressed: _isProcessing
                  ? null
                  : () => _createOrOpenCheckout(booking, paymentUrl),
            )
          else if (isAwaitingPayment && holdExpired)
            _buildMessage(
              'Waktu hold berakhir. Silakan buat booking baru untuk memilih slot lagi.',
              isError: true,
            ),
          const SizedBox(height: 12),
          AppButton(
            label: isAwaitingPayment
                ? 'Saya sudah membayar - cek status booking'
                : 'Lihat status booking',
            isOutlined: true,
            onPressed: () =>
                context.pushReplacement('/booking-status/${booking.id}'),
          ),
        ],
      ),
    );
  }

  Future<void> _createOrOpenCheckout(
    BookingHold booking,
    String? existingUrl,
  ) async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    try {
      var checkoutUrl = existingUrl;
      if (checkoutUrl == null) {
        final mobile = _mobileController.text.trim();
        if (mobile.isEmpty) {
          setState(
            () => _errorMessage = 'Masukkan nomor ponsel untuk checkout.',
          );
          return;
        }

        final checkout = await ref
            .read(bookingRepositoryProvider)
            .createMayarCheckout(bookingId: booking.id, mobile: mobile);
        checkoutUrl = checkout.checkoutUrl;
        if (mounted) setState(() => _checkoutUrl = checkoutUrl);
      }

      final opened = await launchUrl(
        Uri.parse(checkoutUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        setState(() {
          _errorMessage =
              'Tautan Mayar sudah dibuat, tetapi tidak dapat dibuka di perangkat ini.';
        });
        return;
      }

      if (mounted) {
        setState(() {
          _infoMessage =
              'Selesaikan pembayaran di halaman Mayar, lalu kembali dan periksa status booking.';
        });
        ref.invalidate(serverBookingProvider(booking.id));
      }
    } on DioException catch (error) {
      if (mounted) {
        setState(() => _errorMessage = _checkoutErrorMessage(error));
      }
    } on FormatException {
      if (mounted) {
        setState(() {
          _errorMessage = 'Respons checkout dari server tidak valid.';
        });
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Widget _buildLoadError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Data booking tidak dapat dimuat dari server.'),
            const SizedBox(height: 12),
            AppButton(
              label: 'Coba lagi',
              onPressed: () =>
                  ref.invalidate(serverBookingProvider(widget.bookingId)),
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
        Text(label, style: const TextStyle(color: AppColors.textSecondary)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMessage(String message, {bool isError = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        message,
        style: TextStyle(
          color: isError ? AppColors.danger : AppColors.textSecondary,
          fontSize: 13,
        ),
      ),
    );
  }

  String _checkoutErrorMessage(DioException error) {
    final statusCode = error.response?.statusCode;
    final body = error.response?.data;
    final code = body is Map ? body['code'] : null;
    final providerStatus = body is Map ? body['provider_status'] : null;

    return switch (code) {
      'booking_hold_expired' =>
        'Waktu hold berakhir. Silakan buat booking baru.',
      'booking_not_payable' =>
        'Booking ini tidak lagi menunggu pembayaran. Periksa status booking.',
      'patient_profile_incomplete' =>
        'Profil pasien memerlukan nama dan email sebelum pembayaran.',
      'mayar_not_configured' =>
        'Mayar belum dikonfigurasi di backend. Hubungi pengelola aplikasi.',
      'mayar_auth_failed' =>
        'Mayar menolak API key atau izinnya. Pengelola perlu memeriksa API key Sandbox dan akses Read & Write di backend.',
      'mayar_request_rejected' =>
        'Mayar menolak data invoice${providerStatus is int ? ' (HTTP $providerStatus)' : ''}. Pastikan nomor ponsel dan data profil valid, lalu coba lagi.',
      'mayar_rate_limited' =>
        'Mayar membatasi permintaan. Tunggu sebentar sebelum mencoba lagi.',
      'mayar_invalid_response' =>
        'Respons invoice dari Mayar tidak sesuai. Periksa versi API dan konfigurasi backend.',
      'mayar_tls_error' =>
        'Backend gagal membuat koneksi HTTPS aman ke Mayar (TLS). Coba jaringan lain atau periksa VPN, proxy, firewall, dan pemeriksaan SSL pada komputer yang menjalankan Laravel.',
      'mayar_unavailable' =>
        'Mayar sedang tidak dapat dihubungi. Coba lagi beberapa saat.',
      _ when statusCode == 401 => 'Sesi login berakhir. Silakan masuk kembali.',
      _ when statusCode != null && statusCode >= 500 =>
        'Server sedang bermasalah (HTTP $statusCode). Coba lagi nanti.',
      _ when error.response == null =>
        'Tidak dapat terhubung ke server. Periksa jaringan dan backend.',
      _ => 'Checkout gagal (HTTP $statusCode). Periksa data lalu coba lagi.',
    };
  }
}
