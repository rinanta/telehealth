import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:telebunda_app/data/models/booking_hold_model.dart';
import 'package:telebunda_app/data/repositories/booking_repository.dart';
import 'package:telebunda_app/features/booking/screens/booking_status_screen.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('id_ID', null);
  });

  testWidgets('shows server booking status, server fee, and hold countdown', (
    tester,
  ) async {
    final now = DateTime.now();
    final bookingHold = BookingHold(
      id: 'booking-123',
      patientId: 'patient-123',
      midwifeId: 'midwife-123',
      slotId: 'slot-123',
      slotStartAt: now.add(const Duration(days: 1)),
      amount: 82500,
      status: 'awaiting_payment',
      createdAt: now,
      holdExpiresAt: now.add(const Duration(minutes: 15)),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bookingRepositoryProvider.overrideWithValue(
            _RefreshingBookingRepository(bookingHold),
          ),
        ],
        child: MaterialApp(
          home: BookingStatusScreen(
            bookingId: bookingHold.id,
            bookingHold: bookingHold,
          ),
        ),
      ),
    );

    expect(find.text('Menunggu Bayar'), findsOneWidget);
    expect(find.text('Rp 82.500'), findsOneWidget);
    expect(find.byKey(const Key('booking-hold-countdown')), findsOneWidget);
    expect(find.textContaining('Slot ditahan sampai'), findsOneWidget);
    expect(find.textContaining('Booking menunggu pembayaran.'), findsOneWidget);
    expect(find.text('Lanjutkan Pembayaran'), findsOneWidget);
  });

  testWidgets('refreshes booking status after server payment verification', (
    tester,
  ) async {
    final now = DateTime.now();
    final bookingHold = BookingHold(
      id: 'booking-123',
      patientId: 'patient-123',
      midwifeId: 'midwife-123',
      slotId: 'slot-123',
      slotStartAt: now.add(const Duration(days: 1)),
      amount: 82500,
      status: 'awaiting_payment',
      createdAt: now,
      holdExpiresAt: now.add(const Duration(minutes: 15)),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bookingRepositoryProvider.overrideWithValue(
            _RefreshingBookingRepository(bookingHold),
          ),
        ],
        child: MaterialApp(
          home: BookingStatusScreen(
            bookingId: bookingHold.id,
            bookingHold: bookingHold,
          ),
        ),
      ),
    );

    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    expect(find.text('Menunggu Bidan'), findsOneWidget);
    expect(find.byKey(const Key('booking-hold-countdown')), findsNothing);
    expect(
      find.text('Pembayaran telah diverifikasi. Menunggu konfirmasi bidan.'),
      findsOneWidget,
    );
  });

  testWidgets('restores a server booking when route extras are unavailable', (
    tester,
  ) async {
    final now = DateTime.now();
    final bookingHold = BookingHold(
      id: 'booking-123',
      patientId: 'patient-123',
      midwifeId: 'midwife-123',
      slotId: 'slot-123',
      slotStartAt: now.add(const Duration(days: 1)),
      amount: 82500,
      status: 'awaiting_payment',
      createdAt: now,
      holdExpiresAt: now.add(const Duration(minutes: 15)),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bookingRepositoryProvider.overrideWithValue(
            _RefreshingBookingRepository(bookingHold),
          ),
        ],
        child: const MaterialApp(
          home: BookingStatusScreen(bookingId: 'booking-123'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Menunggu Bidan'), findsOneWidget);
    expect(
      find.text('Pembayaran telah diverifikasi. Menunggu konfirmasi bidan.'),
      findsOneWidget,
    );
  });
}

class _RefreshingBookingRepository extends BookingRepository {
  final BookingHold bookingHold;

  _RefreshingBookingRepository(this.bookingHold);

  @override
  Future<BookingHold> fetchBookingById(String bookingId) async {
    return BookingHold(
      id: bookingHold.id,
      patientId: bookingHold.patientId,
      midwifeId: bookingHold.midwifeId,
      slotId: bookingHold.slotId,
      slotStartAt: bookingHold.slotStartAt,
      amount: bookingHold.amount,
      status: 'paid_pending_midwife',
      createdAt: bookingHold.createdAt,
      holdExpiresAt: bookingHold.holdExpiresAt,
    );
  }
}
