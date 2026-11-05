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

class PaymentCheckoutScreen extends ConsumerStatefulWidget {
  final String bookingId;

  const PaymentCheckoutScreen({super.key, required this.bookingId});

  @override
  ConsumerState<PaymentCheckoutScreen> createState() =>
      _PaymentCheckoutScreenState();
}

class _PaymentCheckoutScreenState extends ConsumerState<PaymentCheckoutScreen> {
  final _mobileController = TextEditingController();
  Timer? _timer;
  Timer? _statusTimer;
  DateTime _now = DateTime.now();
  bool _leavingAfterVerifiedPayment = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _statusTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted && _checkoutUrl != null && !_isCheckingStatus) {
        _refreshPaymentStatus();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _statusTimer?.cancel();
    _mobileController.dispose();
    super.dispose();
  }

  void _refreshPaymentStatus() {
    ref.invalidate(serverBookingProvider(widget.bookingId));
  }

  Future<void> _redirectAfterPaid(BookingHold booking) async {
    if (_leavingAfterVerifiedPayment || booking.status != 'paid_pending_midwife') return;
    _leavingAfterVerifiedPayment = true;
    _statusTimer?.cancel();
    if (!mounted) return;
    setState(() => _infoMessage = 'Pembayaran terverifikasi. Mengarahkan ke beranda...');
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (mounted) context.go('/patient-dashboard');
  }

  bool _isProcessing = false;
  bool _isCheckingStatus = false;
  String? _checkoutUrl;
  String? _errorMessage;
  String? _infoMessage;

  @override
  Widget build(BuildContext context) {
    final bookingAsync = ref.watch(serverBookingProvider(widget.bookingId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Pembayaran Midtrans Sandbox')),
      body: bookingAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _buildLoadError(),
        data: (booking) {
          if (booking.status == 'paid_pending_midwife') {
            _redirectAfterPaid(booking);
          }
          return _buildCheckout(booking);
        },
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
              'Pembayaran diproses melalui halaman resmi Midtrans. Status booking akan berubah otomatis setelah pembayaran berhasil dikonfirmasi.',
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
              backgroundColor: AppColors.paymentAccent,
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
            isLoading: _isCheckingStatus,
            onPressed: _isCheckingStatus
                ? null
                : () => _checkPaymentStatus(booking),
          ),
        ],
      ),
    );
  }

  Future<void> _checkPaymentStatus(BookingHold booking) async {
    setState(() {
      _isCheckingStatus = true;
      _errorMessage = null;
      _infoMessage = 'Memeriksa status pembayaran...';
    });

    try {
      ref.invalidate(serverBookingProvider(booking.id));
      final latest = await ref.read(serverBookingProvider(booking.id).future);
      if (!mounted) return;
      if (latest.status == 'awaiting_payment') {
        setState(() {
          _infoMessage = 'Pembayaran belum terverifikasi. Jika sudah membayar, tunggu beberapa saat lalu coba lagi.';
        });
      } else if (latest.status == 'expired') {
        setState(() {
          _errorMessage = 'Waktu pembayaran sudah berakhir. Silakan buat booking baru.';
        });
      } else {
        setState(() {
          _infoMessage = 'Status pembayaran sudah diperbarui.';
        });
      }
    } on DioException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = _checkoutErrorMessage(error));
    } finally {
      if (mounted) setState(() => _isCheckingStatus = false);
    }
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
            .createPaymentCheckout(bookingId: booking.id, mobile: mobile);
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
              'Tautan pembayaran sudah dibuat, tetapi tidak dapat dibuka di perangkat ini.';
        });
        return;
      }

      if (mounted) {
        setState(() {
          _infoMessage =
              'Selesaikan pembayaran di halaman Midtrans, lalu kembali dan periksa status booking.';
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
          _errorMessage = 'Checkout belum dapat diproses. Silakan coba lagi.';
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
            const Text('Data booking belum dapat dimuat. Coba lagi.'),
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

    return switch (code) {
      'booking_hold_expired' =>
        'Waktu hold berakhir. Silakan buat booking baru.',
      'booking_not_payable' =>
        'Booking ini tidak lagi menunggu pembayaran. Periksa status booking.',
      'patient_profile_incomplete' =>
        'Profil pasien memerlukan nama dan email sebelum pembayaran.',
      'payment_not_configured' =>
        'Layanan pembayaran belum tersedia. Silakan coba lagi nanti.',
      'payment_auth_failed' =>
        'Layanan pembayaran sedang bermasalah. Silakan coba lagi nanti.',
      'payment_request_rejected' =>
        'Data pembayaran tidak dapat diproses. Pastikan nomor ponsel dan data profil sudah benar.',
      'payment_rate_limited' =>
        'Terlalu banyak percobaan pembayaran. Tunggu sebentar sebelum mencoba lagi.',
      'payment_invalid_response' =>
        'Pembayaran belum dapat diproses. Silakan coba lagi nanti.',
      'payment_tls_error' =>
        'Pembayaran belum dapat dihubungi dengan aman. Periksa koneksi internet lalu coba lagi.',
      'payment_unavailable' =>
        'Layanan pembayaran sedang tidak tersedia. Silakan coba lagi beberapa saat.',
      _ when statusCode == 401 => 'Sesi masuk sudah berakhir. Silakan masuk kembali.',
      _ when statusCode != null && statusCode >= 500 =>
        'Pembayaran sedang mengalami gangguan. Silakan coba lagi nanti.',
      _ when error.response == null =>
        'Tidak dapat terhubung. Periksa koneksi internet lalu coba lagi.',
      _ => 'Pembayaran belum dapat diproses. Periksa data lalu coba lagi.',
    };
  }
}
