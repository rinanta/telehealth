import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/booking_model.dart';
import '../models/consultation_result_model.dart';
import '../models/midwife_model.dart';
import '../models/slot_model.dart';
import '../models/user_model.dart';

class BookingRepository {
  final _uuid = const Uuid();

  // In-memory list booking untuk demo end-to-end
  final List<Booking> _bookings = [];
  final Map<String, ConsultationResult> _results = {};

  BookingRepository() {
    _seedInitialData();
  }

  void _seedInitialData() {
    final now = DateTime.now();

    // 1. Booking yang sudah selesai untuk riwayat pasien (UI-11) & bidan (UI-15)
    final completedBooking = Booking(
      id: 'book_history_001',
      patientId: 'patient_001',
      patientName: 'Bunda Anisa Lestari',
      midwifeId: 'midwife_001',
      midwifeName: 'Bdn. Siti Rahmawati, S.Tr.Keb',
      slotId: 'slot_prev_01',
      slotStartAt: now.subtract(const Duration(days: 3)),
      complaint: 'Sering pusing ringan di pagi hari dan kram perut sesekali saat bangun tidur.',
      amount: 50000,
      status: 'completed',
      paymentId: 'mayar_pay_9981',
      consultationStartedAt: now.subtract(const Duration(days: 3, minutes: 40)),
      consultationCompletedAt: now.subtract(const Duration(days: 3, minutes: 10)),
      createdAt: now.subtract(const Duration(days: 4)),
    );

    _bookings.add(completedBooking);
    _results[completedBooking.id] = ConsultationResult(
      id: 'result_001',
      consultationId: 'cons_001',
      bookingId: completedBooking.id,
      patientName: completedBooking.patientName,
      midwifeName: completedBooking.midwifeName,
      summary: 'Pasien trimester 2 mengeluhkan pusing ortostatik ringan dan kram ligamen (round ligament pain). Tanda vital dalam batas aman.',
      advice: 'Hindari perubahan posisi mendadak dari tidur ke berdiri. Cukupi asupan cairan minimal 2.5 liter per hari. Lakukan peregangan pinggul secara perlahan.',
      supplementNote: 'Lanjutkan Tablet Tambah Darah (Fe) 1x1 malam hari dan Kalsium 500mg 1x1 pagi hari setelah makan.',
      followUp: 'Jika pusing disertai pandangan kabur atau nyeri ulu hati hebat, segera periksa ke fasilitas kesehatan darurat. Kontrol ANC rutin 2 minggu lagi.',
      savedBy: 'Bdn. Siti Rahmawati, S.Tr.Keb',
      completedAt: now.subtract(const Duration(days: 3, minutes: 10)),
    );

    // 2. Booking menunggu konfirmasi bidan (paid_pending_midwife) untuk demo UI-12 & UI-13
    final pendingMidwifeBooking = Booking(
      id: 'book_pending_002',
      patientId: 'patient_001',
      patientName: 'Bunda Anisa Lestari',
      midwifeId: 'midwife_001',
      midwifeName: 'Bdn. Siti Rahmawati, S.Tr.Keb',
      slotId: 'slot_today_01',
      slotStartAt: now.add(const Duration(hours: 1)),
      complaint: 'Perut terasa kencang saat lelah beraktivitas kantor, ingin konsultasi persiapan nutrisi trimester 3.',
      amount: 50000,
      status: 'paid_pending_midwife',
      paymentId: 'mayar_sandbox_pay_7721',
      checkoutUrl: 'https://sandbox.mayar.id/checkout/telebunda-demo-7721',
      createdAt: now.subtract(const Duration(minutes: 15)),
    );
    _bookings.add(pendingMidwifeBooking);
  }

  List<Booking> getAllBookings() => List.unmodifiable(_bookings);

  List<Booking> getBookingsForPatient(String patientId) {
    return _bookings.where((b) => b.patientId == patientId).toList();
  }

  List<Booking> getBookingsForMidwife(String midwifeId) {
    return _bookings.where((b) => b.midwifeId == midwifeId).toList();
  }

  Booking? getBookingById(String id) {
    try {
      return _bookings.firstWhere((b) => b.id == id);
    } catch (_) {
      return null;
    }
  }

  ConsultationResult? getResultByBookingId(String bookingId) {
    return _results[bookingId];
  }

  // FR-06: Buat booking + hold slot -> awaiting_payment
  Future<Booking> createBooking({
    required AppUser patient,
    required Midwife midwife,
    required ConsultationSlot slot,
    required String complaint,
  }) async {
    await Future.delayed(const Duration(milliseconds: 600));

    final bookingId = 'book_${_uuid.v4().substring(0, 8)}';
    final paymentId = 'mayar_sb_${_uuid.v4().substring(0, 8)}';
    final checkoutUrl = 'https://sandbox.mayar.id/checkout/telebunda-$bookingId';

    final booking = Booking(
      id: bookingId,
      patientId: patient.uid,
      patientName: patient.name,
      midwifeId: midwife.uid,
      midwifeName: midwife.name,
      slotId: slot.id,
      slotStartAt: slot.startAt,
      complaint: complaint,
      amount: midwife.price,
      status: 'awaiting_payment',
      paymentId: paymentId,
      checkoutUrl: checkoutUrl,
      createdAt: DateTime.now(),
    );

    _bookings.insert(0, booking);
    return booking;
  }

  // FR-07 & FR-08: Simulasi Mayar Sandbox Webhook -> paid_pending_midwife
  Future<Booking> simulateMayarPaymentSuccess(String bookingId) async {
    await Future.delayed(const Duration(milliseconds: 800));

    final index = _bookings.indexWhere((b) => b.id == bookingId);
    if (index == -1) throw Exception('Booking tidak ditemukan');

    final updated = _bookings[index].copyWith(
      status: 'paid_pending_midwife',
    );
    _bookings[index] = updated;
    return updated;
  }

  // FR-09: Bidan menerima booking -> confirmed
  Future<Booking> midwifeAcceptBooking(String bookingId) async {
    await Future.delayed(const Duration(milliseconds: 500));

    final index = _bookings.indexWhere((b) => b.id == bookingId);
    if (index == -1) throw Exception('Booking tidak ditemukan');

    final updated = _bookings[index].copyWith(
      status: 'confirmed',
    );
    _bookings[index] = updated;
    return updated;
  }

  // Bidan menolak booking -> rejected
  Future<Booking> midwifeRejectBooking(String bookingId, String reason) async {
    await Future.delayed(const Duration(milliseconds: 500));

    final index = _bookings.indexWhere((b) => b.id == bookingId);
    if (index == -1) throw Exception('Booking tidak ditemukan');

    final updated = _bookings[index].copyWith(
      status: 'rejected',
      rejectionReason: reason,
    );
    _bookings[index] = updated;
    return updated;
  }

  // FR-10 & FR-11: Bidan / Jadwal membuka sesi -> active, catat startedAt
  Future<Booking> startConsultation(String bookingId) async {
    await Future.delayed(const Duration(milliseconds: 400));

    final index = _bookings.indexWhere((b) => b.id == bookingId);
    if (index == -1) throw Exception('Booking tidak ditemukan');

    final updated = _bookings[index].copyWith(
      status: 'active',
      consultationStartedAt: DateTime.now(),
    );
    _bookings[index] = updated;
    return updated;
  }

  // FR-12: Bidan menyimpan form hasil & menyelesaikan konsultasi -> completed
  Future<Booking> completeConsultation({
    required String bookingId,
    required String summary,
    required String advice,
    String? supplementNote,
    required String followUp,
    required String savedBy,
  }) async {
    await Future.delayed(const Duration(milliseconds: 700));

    final index = _bookings.indexWhere((b) => b.id == bookingId);
    if (index == -1) throw Exception('Booking tidak ditemukan');

    final now = DateTime.now();
    final updated = _bookings[index].copyWith(
      status: 'completed',
      consultationCompletedAt: now,
    );
    _bookings[index] = updated;

    _results[bookingId] = ConsultationResult(
      id: 'res_${_uuid.v4().substring(0, 8)}',
      consultationId: 'cons_$bookingId',
      bookingId: bookingId,
      patientName: updated.patientName,
      midwifeName: updated.midwifeName,
      summary: summary,
      advice: advice,
      supplementNote: supplementNote,
      followUp: followUp,
      savedBy: savedBy,
      completedAt: now,
    );

    return updated;
  }
}

// StateNotifier untuk sinkronisasi daftar booking di seluruh aplikasi
class BookingNotifier extends StateNotifier<List<Booking>> {
  final BookingRepository _repo;

  BookingNotifier(this._repo) : super(_repo.getAllBookings());

  void refresh() {
    state = _repo.getAllBookings();
  }

  Future<Booking> createBooking({
    required AppUser patient,
    required Midwife midwife,
    required ConsultationSlot slot,
    required String complaint,
  }) async {
    final booking = await _repo.createBooking(
      patient: patient,
      midwife: midwife,
      slot: slot,
      complaint: complaint,
    );
    refresh();
    return booking;
  }

  Future<Booking> simulatePayment(String bookingId) async {
    final updated = await _repo.simulateMayarPaymentSuccess(bookingId);
    refresh();
    return updated;
  }

  Future<Booking> midwifeAccept(String bookingId) async {
    final updated = await _repo.midwifeAcceptBooking(bookingId);
    refresh();
    return updated;
  }

  Future<Booking> midwifeReject(String bookingId, String reason) async {
    final updated = await _repo.midwifeRejectBooking(bookingId, reason);
    refresh();
    return updated;
  }

  Future<Booking> startConsultation(String bookingId) async {
    final updated = await _repo.startConsultation(bookingId);
    refresh();
    return updated;
  }

  Future<Booking> completeConsultation({
    required String bookingId,
    required String summary,
    required String advice,
    String? supplementNote,
    required String followUp,
    required String savedBy,
  }) async {
    final updated = await _repo.completeConsultation(
      bookingId: bookingId,
      summary: summary,
      advice: advice,
      supplementNote: supplementNote,
      followUp: followUp,
      savedBy: savedBy,
    );
    refresh();
    return updated;
  }
}

final bookingRepositoryProvider = Provider<BookingRepository>((ref) => BookingRepository());

final bookingsListProvider = StateNotifierProvider<BookingNotifier, List<Booking>>((ref) {
  final repo = ref.watch(bookingRepositoryProvider);
  return BookingNotifier(repo);
});
