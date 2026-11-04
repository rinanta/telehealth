import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telebunda_app/core/widgets/consultation_timer_banner.dart';
import 'package:telebunda_app/core/widgets/status_badge.dart';
import 'package:telebunda_app/data/models/booking_model.dart';

void main() {
  group('Booking model endsAt & no_show', () {
    test('parses ends_at and correctly detects no_show status', () {
      final json = {
        'id': 'booking-test',
        'patient_id': 'patient-1',
        'patient_name': 'Bunda',
        'midwife_id': 'midwife-1',
        'midwife_name': 'Bidan',
        'slot_id': 'slot-1',
        'slot_start_at': '2026-11-05T10:00:00Z',
        'complaint': 'Keluhan.',
        'amount': 75000,
        'status': 'no_show',
        'consultation_started_at': '2026-11-05T10:00:00Z',
        'ends_at': '2026-11-05T10:30:00Z',
        'created_at': '2026-11-04T04:00:00Z',
      };

      final booking = Booking.fromJson(json);

      expect(booking.isNoShow, true);
      expect(booking.statusLabel, 'Tidak Hadir');
      expect(booking.endsAt, DateTime.parse('2026-11-05T10:30:00Z'));
      expect(booking.toJson()['ends_at'], '2026-11-05T10:30:00.000Z');
    });

    testWidgets('StatusBadge renders Tidak Hadir for no_show status', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatusBadge(status: 'no_show'),
          ),
        ),
      );

      expect(find.text('Tidak Hadir'), findsOneWidget);
      expect(find.byIcon(Icons.person_off_outlined), findsOneWidget);
    });

    testWidgets('ConsultationTimerBanner prioritizes server endsAt when provided', (tester) async {
      final now = DateTime.now();
      // Server ends_at is exactly 120 seconds in the future
      final serverEndsAt = now.add(const Duration(seconds: 120));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConsultationTimerBanner(
              startedAt: now.subtract(const Duration(minutes: 50)), // Past startedAt
              endsAt: serverEndsAt, // Authoritative server endsAt
              durationMinutes: 30,
            ),
          ),
        ),
      );

      await tester.pump();

      // Should show active countdown banner based on serverEndsAt, not expired!
      expect(find.text('Waktu Konsultasi Telah Berakhir (30 Menit)'), findsNothing);
      expect(find.textContaining(RegExp(r'0[12]:[0-5][0-9]')), findsOneWidget);
    });

    testWidgets('expired timer callback is deferred until after the build', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: _TimerCallbackHost()),
      );

      await tester.pump();

      expect(find.text('expired'), findsOneWidget);
    });
  });
}

class _TimerCallbackHost extends StatefulWidget {
  const _TimerCallbackHost();

  @override
  State<_TimerCallbackHost> createState() => _TimerCallbackHostState();
}

class _TimerCallbackHostState extends State<_TimerCallbackHost> {
  bool _expired = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          ConsultationTimerBanner(
            startedAt: DateTime(2020),
            onTimerExpired: () => setState(() => _expired = true),
          ),
          if (_expired) const Text('expired'),
        ],
      ),
    );
  }
}
