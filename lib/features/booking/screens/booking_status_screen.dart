import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../data/models/booking_model.dart';
import '../../../data/models/booking_hold_model.dart';
import '../../../data/repositories/booking_repository.dart';

class BookingStatusScreen extends ConsumerWidget {
  final String bookingId;
  final BookingHold? bookingHold;

  const BookingStatusScreen({
    super.key,
    required this.bookingId,
    this.bookingHold,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (bookingHold != null) {
      return _ServerBookingHoldStatus(bookingHold: bookingHold!);
    }

    final bookings = ref.watch(bookingsListProvider);
    final booking = bookings.cast<Booking?>().firstWhere(
      (b) => b?.id == bookingId,
      orElse: () => null,
    );

    if (booking == null) {
      return _ServerBookingStatusLoader(bookingId: bookingId);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Status & Jadwal Konsultasi'),
        actions: [
          IconButton(
            tooltip: 'Ke Beranda',
            icon: const Icon(Icons.home_outlined),
            onPressed: () => context.go('/patient-dashboard'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Header
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
                      const Text(
                        'Status Reservasi Saat Ini',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      StatusBadge(status: booking.status),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    booking.midwifeName,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_rounded,
                        size: 14,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        Formatters.formatDateTime(booking.slotStartAt),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Stepper Status Sesuai PRD State Machine
            const Text(
              'Alur Proses Reservasi',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  _buildStepItem(
                    title: '1. Pembuatan Reservasi & Hold Slot',
                    subtitle: 'Slot waktu berhasil ditahan sementara',
                    isDone: true,
                    isActive: false,
                  ),
                  _buildStepDivider(true),
                  _buildStepItem(
                    title: '2. Pembayaran Midtrans Sandbox',
                    subtitle: booking.isAwaitingPayment
                        ? 'Menunggu pembayaran di sandbox gateway'
                        : 'Pembayaran berhasil dikonfirmasi',
                    isDone: !booking.isAwaitingPayment,
                    isActive: booking.isAwaitingPayment,
                  ),
                  _buildStepDivider(!booking.isAwaitingPayment),
                  _buildStepItem(
                    title: '3. Konfirmasi dari Bidan',
                    subtitle: booking.isPaidPendingMidwife
                        ? 'Menunggu Bidan menerima jadwal reservasi'
                        : (booking.isConfirmed ||
                              booking.isActive ||
                              booking.isCompleted)
                        ? 'Bidan telah mengonfirmasi kehadiran'
                        : 'Menunggu konfirmasi',
                    isDone:
                        booking.isConfirmed ||
                        booking.isActive ||
                        booking.isCompleted,
                    isActive: booking.isPaidPendingMidwife,
                  ),
                  _buildStepDivider(
                    booking.isConfirmed ||
                        booking.isActive ||
                        booking.isCompleted,
                  ),
                  _buildStepItem(
                    title: '4. Sesi Konsultasi Chat (30 Menit)',
                    subtitle: booking.isActive
                        ? 'Sesi sedang berlangsung! Silakan masuk ruang chat.'
                        : booking.isCompleted
                        ? 'Sesi 30 menit selesai'
                        : 'Tombol chat akan dibuka saat sesi dimulai',
                    isDone: booking.isCompleted,
                    isActive: booking.isActive,
                  ),
                  _buildStepDivider(booking.isCompleted),
                  _buildStepItem(
                    title: '5. Rekap Hasil Konsultasi Medis',
                    subtitle: booking.isCompleted
                        ? 'Hasil pemeriksaan dan saran bidan telah siap'
                        : 'Disusun oleh bidan setelah sesi selesai',
                    isDone: booking.isCompleted,
                    isActive: false,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Aksi Sesuai Status
            if (booking.isActive)
              AppButton(
                label: 'Masuk ke Ruang Chat Konsultasi Sekarang',
                icon: Icons.chat_rounded,
                backgroundColor: AppColors.success,
                onPressed: () =>
                    context.push('/consultation-chat/${booking.id}'),
              )
            else if (booking.isCompleted)
              AppButton(
                label: 'Lihat Hasil Konsultasi & Catatan Bidan',
                icon: Icons.description_outlined,
                onPressed: () =>
                    context.push('/consultation-result/${booking.id}'),
              )
            else if (booking.isAwaitingPayment)
              AppButton(
                label: 'Lanjutkan Pembayaran Sandbox',
                icon: Icons.payment,
                backgroundColor: AppColors.paymentAccent,
                onPressed: () => context.push('/payment-checkout/${booking.id}'),
              )
            else if (booking.isConfirmed)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.lock_clock,
                      color: AppColors.secondary,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Jadwal terkonfirmasi. Chat akan aktif saat Bidan membuka sesi sesuai waktu konsultasi.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.secondaryDark,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else if (booking.isPaidPendingMidwife)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.infoContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.hourglass_top,
                      color: AppColors.info,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Pembayaran Anda telah diterima. Menunggu Bidan mengonfirmasi jadwal.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF1E3A8A),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildStepItem({
    required String title,
    required String subtitle,
    required bool isDone,
    required bool isActive,
  }) {
    Color iconColor;
    IconData icon;

    if (isDone) {
      iconColor = AppColors.success;
      icon = Icons.check_circle_rounded;
    } else if (isActive) {
      iconColor = AppColors.primary;
      icon = Icons.radio_button_checked;
    } else {
      iconColor = AppColors.textMuted;
      icon = Icons.radio_button_unchecked;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: iconColor),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: (isDone || isActive)
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: (isDone || isActive)
                      ? AppColors.textPrimary
                      : AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStepDivider(bool isDone) {
    return Container(
      margin: const EdgeInsets.only(left: 9, top: 4, bottom: 4),
      height: 18,
      width: 2,
      color: isDone ? AppColors.success : AppColors.border,
    );
  }
}

class _ServerBookingStatusLoader extends ConsumerWidget {
  final String bookingId;

  const _ServerBookingStatusLoader({required this.bookingId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booking = ref.watch(serverBookingProvider(bookingId));

    return booking.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, stackTrace) => Scaffold(
        appBar: AppBar(title: const Text('Status Reservasi')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Status booking belum dapat dimuat. Periksa koneksi lalu coba lagi.'),
              TextButton(
                onPressed: () =>
                    ref.invalidate(serverBookingProvider(bookingId)),
                child: const Text('Coba lagi'),
              ),
            ],
          ),
        ),
      ),
      data: (bookingHold) => _ServerBookingHoldStatus(bookingHold: bookingHold),
    );
  }
}

class _ServerBookingHoldStatus extends ConsumerStatefulWidget {
  final BookingHold bookingHold;

  const _ServerBookingHoldStatus({required this.bookingHold});

  @override
  ConsumerState<_ServerBookingHoldStatus> createState() =>
      _ServerBookingHoldStatusState();
}

class _ServerBookingHoldStatusState
    extends ConsumerState<_ServerBookingHoldStatus> {
  Timer? _countdownTimer;
  Timer? _refreshTimer;
  late int _secondsRemaining;
  late BookingHold _booking;
  String? _refreshError;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _booking = widget.bookingHold;
    _secondsRemaining = _remainingSecondsUntilExpiry();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final remaining = _remainingSecondsUntilExpiry();
      if (remaining != _secondsRemaining && mounted) {
        setState(() => _secondsRemaining = remaining);
      }
      if (remaining == 0) {
        _countdownTimer?.cancel();
      }
    });
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_booking.status == 'awaiting_payment' ||
          _booking.status == 'paid_pending_midwife' ||
          _booking.status == 'confirmed' ||
          _booking.status == 'active') {
        _refreshBooking();
      }
    });
  }

  Future<void> _refreshBooking() async {
    if (_isRefreshing) return;
    _isRefreshing = true;

    try {
      final booking = await ref
          .read(bookingRepositoryProvider)
          .fetchBookingById(widget.bookingHold.id);
      if (!mounted) return;
      setState(() {
        _booking = booking;
        _refreshError = null;
        _secondsRemaining = _remainingSecondsUntilExpiry();
      });
    } on DioException {
      if (!mounted) return;
      setState(() {
        _refreshError = 'Status belum dapat diperbarui. Memeriksa lagi...';
      });
    } on FormatException {
      if (!mounted) return;
      setState(() {
        _refreshError = 'Respons status booking dari server tidak valid.';
      });
    } finally {
      _isRefreshing = false;
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  int _remainingSecondsUntilExpiry() {
    final remaining = _booking.holdExpiresAt
        .difference(DateTime.now())
        .inSeconds;
    return remaining < 0 ? 0 : remaining;
  }

  @override
  Widget build(BuildContext context) {
    final booking = _booking;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Status Reservasi'),
        actions: [
          IconButton(
            tooltip: 'Perbarui Status',
            icon: _isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isRefreshing ? null : _refreshBooking,
          ),
          IconButton(
            tooltip: 'Ke Beranda',
            icon: const Icon(Icons.home_outlined),
            onPressed: () => context.go('/patient-dashboard'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshBooking,
        child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
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
                const Text(
                  'Status booking',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                StatusBadge(status: booking.status),
                const SizedBox(height: 16),
                _BookingDetailRow(
                  label: 'Tarif konsultasi',
                  value: Formatters.toRupiah(booking.amount),
                  valueKey: const Key('server-booking-amount'),
                ),
                const SizedBox(height: 10),
                _BookingDetailRow(
                  label: 'Jadwal konsultasi',
                  value: Formatters.formatDateTime(booking.slotStartAt),
                ),
                const SizedBox(height: 10),
                _BookingDetailRow(label: 'ID reservasi', value: booking.id),
              ],
            ),
          ),
          if (booking.status == 'awaiting_payment') ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  const Text(
                    'Waktu hold tersisa',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    Formatters.formatTimer(_secondsRemaining),
                    key: const Key('booking-hold-countdown'),
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _secondsRemaining > 0
                        ? 'Slot ditahan sampai ${Formatters.formatTime(booking.holdExpiresAt)}.'
                        : 'Waktu hold tercapai. Memeriksa status terbaru dari server.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (_secondsRemaining > 0) ...[
              const SizedBox(height: 16),
              AppButton(
                label: 'Lanjutkan Pembayaran',
                icon: Icons.payment,
                backgroundColor: AppColors.paymentAccent,
                onPressed: () => context.push('/payment-checkout/${booking.id}'),
              ),
            ],
          ],
          if (booking.status == 'active') ...[
            const SizedBox(height: 16),
            AppButton(
              label: 'Masuk ke Ruang Chat Konsultasi',
              icon: Icons.chat_rounded,
              backgroundColor: AppColors.success,
              onPressed: () => context.push('/consultation-chat/${booking.id}'),
            ),
          ],
          if (_refreshError != null) ...[
            const SizedBox(height: 12),
            Text(
              _refreshError!,
              key: const Key('booking-refresh-error'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            _bookingStatusMessage(booking.status),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    ),
  );
  }

  String _bookingStatusMessage(String status) {
    return switch (status) {
      'awaiting_payment' =>
        'Booking menunggu pembayaran. Ketuk Lanjutkan Pembayaran untuk membuka halaman Midtrans; status berubah setelah server memverifikasi pembayaran.',
      'paid_pending_midwife' =>
        'Pembayaran telah diverifikasi. Menunggu konfirmasi bidan.',
      'confirmed' => 'Booking dikonfirmasi. Jadwal konsultasi Anda tercatat.',
      'active' => 'Sesi konsultasi sedang berlangsung.',
      'completed' => 'Sesi konsultasi telah selesai.',
      'expired' => 'Waktu hold habis dan slot telah dilepas oleh server.',
      'payment_failed' => 'Pembayaran gagal. Silakan buat booking baru.',
      'cancelled' => 'Booking dibatalkan.',
      'rejected' => 'Booking ditolak oleh bidan.',
      'no_show' => 'Booking ditandai sebagai tidak hadir.',
      _ => 'Status booking: $status.',
    };
  }
}

class _BookingDetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Key? valueKey;

  const _BookingDetailRow({
    required this.label,
    required this.value,
    this.valueKey,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            key: valueKey,
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
