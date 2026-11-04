import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telebunda_app/data/models/booking_hold_model.dart';
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
      MaterialApp(
        home: BookingStatusScreen(
          bookingId: bookingHold.id,
          bookingHold: bookingHold,
        ),
      ),
    );

    expect(find.text('Menunggu Bayar'), findsOneWidget);
    expect(find.text('Rp 82.500'), findsOneWidget);
    expect(find.byKey(const Key('booking-hold-countdown')), findsOneWidget);
    expect(find.textContaining('Slot ditahan sampai'), findsOneWidget);
    expect(find.textContaining('Pembayaran belum tersedia'), findsOneWidget);
  });
}
