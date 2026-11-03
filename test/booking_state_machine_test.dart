import 'package:flutter_test/flutter_test.dart';
import 'package:telebunda_app/data/models/midwife_model.dart';
import 'package:telebunda_app/data/models/slot_model.dart';
import 'package:telebunda_app/data/models/user_model.dart';
import 'package:telebunda_app/data/repositories/booking_repository.dart';

void main() {
  group('Booking State Machine Tests (PRD Bab 5 & Bab 6)', () {
    late BookingRepository repository;
    late AppUser patient;
    late Midwife midwife;
    late ConsultationSlot slot;

    setUp(() {
      repository = BookingRepository();
      patient = AppUser(
        uid: 'patient_test',
        name: 'Bunda Test',
        email: 'test@bunda.id',
        role: 'patient',
        verified: true,
        createdAt: DateTime.now(),
      );
      midwife = const Midwife(
        uid: 'midwife_test',
        name: 'Bdn. Test, S.Tr.Keb',
        credentialLabel: 'Bidan Test',
        bio: 'Bio test',
        experienceYears: 5,
        price: 50000,
        strNumber: 'STR-TEST-123',
        hospitalAffiliation: 'Klinik Test',
      );
      slot = ConsultationSlot(
        id: 'slot_test_1',
        midwifeId: midwife.uid,
        startAt: DateTime.now().add(const Duration(hours: 2)),
        endAt: DateTime.now().add(const Duration(hours: 2, minutes: 30)),
      );
    });

    test('FR-06: Buat booking awal menghasilkan status awaiting_payment', () async {
      final booking = await repository.createBooking(
        patient: patient,
        midwife: midwife,
        slot: slot,
        complaint: 'Pusing ringan dan mual di pagi hari.',
      );

      expect(booking.status, equals('awaiting_payment'));
      expect(booking.isAwaitingPayment, isTrue);
      expect(booking.amount, equals(50000));
      expect(booking.checkoutUrl, isNotNull);
    });

    test('FR-07 & FR-08: Pembayaran terverifikasi mengubah status menjadi paid_pending_midwife', () async {
      final booking = await repository.createBooking(
        patient: patient,
        midwife: midwife,
        slot: slot,
        complaint: 'Keluhan test',
      );

      final paidBooking = await repository.simulateMayarPaymentSuccess(booking.id);
      expect(paidBooking.status, equals('paid_pending_midwife'));
      expect(paidBooking.isPaidPendingMidwife, isTrue);
    });

    test('FR-09: Bidan menerima booking mengubah status menjadi confirmed', () async {
      final booking = await repository.createBooking(
        patient: patient,
        midwife: midwife,
        slot: slot,
        complaint: 'Keluhan test',
      );
      await repository.simulateMayarPaymentSuccess(booking.id);

      final confirmedBooking = await repository.midwifeAcceptBooking(booking.id);
      expect(confirmedBooking.status, equals('confirmed'));
      expect(confirmedBooking.isConfirmed, isTrue);
    });

    test('FR-10 & FR-11: Mulai sesi konsultasi mengubah status menjadi active dan mencatat startedAt', () async {
      final booking = await repository.createBooking(
        patient: patient,
        midwife: midwife,
        slot: slot,
        complaint: 'Keluhan test',
      );
      await repository.simulateMayarPaymentSuccess(booking.id);
      await repository.midwifeAcceptBooking(booking.id);

      final activeBooking = await repository.startConsultation(booking.id);
      expect(activeBooking.status, equals('active'));
      expect(activeBooking.isActive, isTrue);
      expect(activeBooking.consultationStartedAt, isNotNull);
    });

    test('FR-12: Bidan menyelesaikan konsultasi menghasilkan status completed dan lembar hasil', () async {
      final booking = await repository.createBooking(
        patient: patient,
        midwife: midwife,
        slot: slot,
        complaint: 'Keluhan test',
      );
      await repository.simulateMayarPaymentSuccess(booking.id);
      await repository.midwifeAcceptBooking(booking.id);
      await repository.startConsultation(booking.id);

      final completedBooking = await repository.completeConsultation(
        bookingId: booking.id,
        summary: 'Ringkasan keluhan pasien aman.',
        advice: 'Istirahat dan hidrasi teratur.',
        supplementNote: 'Tablet Fe 1x1.',
        followUp: 'Kontrol 2 minggu lagi.',
        savedBy: midwife.name,
      );

      expect(completedBooking.status, equals('completed'));
      expect(completedBooking.isCompleted, isTrue);

      final result = repository.getResultByBookingId(booking.id);
      expect(result, isNotNull);
      expect(result!.summary, equals('Ringkasan keluhan pasien aman.'));
      expect(result.supplementNote, equals('Tablet Fe 1x1.'));
    });
  });
}
