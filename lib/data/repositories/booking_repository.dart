import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../models/booking_hold_model.dart';
import '../models/booking_model.dart';
import '../models/consultation_result_model.dart';
import '../models/midwife_model.dart';
import '../models/payment_checkout_model.dart';
import '../models/slot_model.dart';
import '../models/user_model.dart';

class BookingRepository {
  final _uuid = const Uuid();
  final ApiClient? _apiClient;
  final List<Booking> _bookings = [];
  final Map<String, ConsultationResult> _results = {};

  BookingRepository({ApiClient? apiClient}) : _apiClient = apiClient;

  // These methods are used only by unit tests without an API client.
  List<Booking> getAllBookings() => List.unmodifiable(_bookings);

  List<Booking> getBookingsForPatient(String patientId) =>
      _bookings.where((booking) => booking.patientId == patientId).toList();

  List<Booking> getBookingsForMidwife(String midwifeId) =>
      _bookings.where((booking) => booking.midwifeId == midwifeId).toList();

  Booking? getBookingById(String id) {
    try {
      return _bookings.firstWhere((booking) => booking.id == id);
    } catch (_) {
      return null;
    }
  }

  ConsultationResult? getResultByBookingId(String bookingId) => _results[bookingId];

  Future<BookingHold> createBookingRequest({
    required ConsultationSlot slot,
    required String complaint,
  }) async {
    final apiClient = _requireApiClient();
    final response = await apiClient.post(
      ApiEndpoints.bookings,
      data: {'slot_id': slot.id, 'complaint': complaint},
    );
    return _bookingHoldFromResponse(response.data);
  }

  Future<BookingHold> fetchBookingById(String bookingId) async {
    final response = await _requireApiClient().get(ApiEndpoints.booking(bookingId));
    return _bookingHoldFromResponse(response.data);
  }

  Future<List<Booking>> getMidwifeBookings() async {
    final response = await _requireApiClient().get(ApiEndpoints.midwifeBookings);
    return _bookingsFromResponse(response.data, 'midwife bookings');
  }

  Future<void> acceptMidwifeBooking(String bookingId) async {
    await _requireApiClient().post(ApiEndpoints.midwifeBookingAccept(bookingId));
  }

  Future<void> rejectMidwifeBooking({
    required String bookingId,
    required String reason,
  }) async {
    await _requireApiClient().post(
      ApiEndpoints.midwifeBookingReject(bookingId),
      data: {'reason': reason},
    );
  }

  Future<void> startMidwifeConsultation(String bookingId) async {
    await _requireApiClient().post(ApiEndpoints.midwifeBookingStart(bookingId));
  }

  Future<void> completeMidwifeConsultation({
    required String bookingId,
    required String summary,
    required String advice,
    String? supplementNote,
    required String followUp,
  }) async {
    final note = supplementNote?.trim() ?? '';
    await _requireApiClient().post(
      ApiEndpoints.midwifeBookingComplete(bookingId),
      data: {
        'summary': summary,
        'advice': advice,
        if (note.isNotEmpty) 'supplement_note': note,
        'follow_up': followUp,
      },
    );
  }

  Future<ConsultationResult?> fetchConsultationResult(String bookingId) async {
    try {
      final response = await _requireApiClient().get(ApiEndpoints.bookingResult(bookingId));
      final payload = response.data;
      if (payload is! Map || payload['data'] is! Map) {
        throw const FormatException('The API returned an invalid consultation result response.');
      }
      return ConsultationResult.fromJson(Map<String, dynamic>.from(payload['data'] as Map));
    } on DioException catch (error) {
      final body = error.response?.data;
      if (error.response?.statusCode == 404 && body is Map && body['code'] == 'result_not_found') {
        return null;
      }
      rethrow;
    }
  }

  Future<List<Booking>> getPatientHistory() async {
    final response = await _requireApiClient().get(ApiEndpoints.history);
    return _bookingsFromResponse(response.data, 'patient history');
  }

  Future<PaymentCheckout> createPaymentCheckout({
    required String bookingId,
    required String mobile,
  }) async {
    final response = await _requireApiClient().post(
      ApiEndpoints.bookingCheckout(bookingId),
      data: {'mobile': mobile},
    );
    final payload = response.data;
    if (payload is! Map || payload['data'] is! Map) {
      throw const FormatException('The API returned an invalid checkout response.');
    }
    return PaymentCheckout.fromJson(Map<String, dynamic>.from(payload['data'] as Map));
  }

  Future<Booking> createBooking({
    required AppUser patient,
    required Midwife midwife,
    required ConsultationSlot slot,
    required String complaint,
  }) async {
    final amount = midwife.price;
    if (amount == null) {
      throw StateError('Harga konsultasi belum ditetapkan oleh server.');
    }

    if (_apiClient != null) {
      final hold = await createBookingRequest(slot: slot, complaint: complaint);
      return Booking(
        id: hold.id,
        patientId: hold.patientId,
        patientName: patient.name,
        midwifeId: hold.midwifeId,
        midwifeName: midwife.name,
        slotId: hold.slotId,
        slotStartAt: hold.slotStartAt,
        complaint: complaint,
        amount: hold.amount,
        status: hold.status,
        paymentId: hold.paymentId,
        checkoutUrl: hold.checkoutUrl,
        createdAt: hold.createdAt,
      );
    }

    final booking = Booking(
      id: 'booking_${_uuid.v4().substring(0, 8)}',
      patientId: patient.uid,
      patientName: patient.name,
      midwifeId: midwife.uid,
      midwifeName: midwife.name,
      slotId: slot.id,
      slotStartAt: slot.startAt,
      complaint: complaint,
      amount: amount,
      status: 'awaiting_payment',
      checkoutUrl: 'https://test.invalid/checkout/${_uuid.v4()}',
      createdAt: DateTime.now(),
    );
    _bookings.insert(0, booking);
    return booking;
  }

  Future<Booking> midwifeAcceptBooking(String bookingId) async {
    final index = _indexOf(bookingId);
    final updated = _bookings[index].copyWith(status: 'confirmed');
    _bookings[index] = updated;
    return updated;
  }

  Future<Booking> midwifeRejectBooking(String bookingId, String reason) async {
    final index = _indexOf(bookingId);
    final updated = _bookings[index].copyWith(status: 'rejected', rejectionReason: reason);
    _bookings[index] = updated;
    return updated;
  }

  Future<Booking> startConsultation(String bookingId) async {
    final index = _indexOf(bookingId);
    final startedAt = DateTime.now();
    final updated = _bookings[index].copyWith(
      status: 'active',
      consultationStartedAt: startedAt,
      endsAt: startedAt.add(const Duration(minutes: 30)),
    );
    _bookings[index] = updated;
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
    final index = _indexOf(bookingId);
    final now = DateTime.now();
    final updated = _bookings[index].copyWith(
      status: 'completed',
      consultationCompletedAt: now,
    );
    _bookings[index] = updated;
    _results[bookingId] = ConsultationResult(
      id: 'test_result_${_uuid.v4().substring(0, 8)}',
      consultationId: 'test_consultation_$bookingId',
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

  ApiClient _requireApiClient() {
    final apiClient = _apiClient;
    if (apiClient == null) {
      throw StateError('The booking API client is not configured.');
    }
    return apiClient;
  }

  BookingHold _bookingHoldFromResponse(dynamic response) {
    if (response is! Map || response['data'] is! Map) {
      throw const FormatException('The API returned an invalid booking response.');
    }
    return BookingHold.fromJson(Map<String, dynamic>.from(response['data'] as Map));
  }

  List<Booking> _bookingsFromResponse(dynamic response, String name) {
    if (response is! Map || response['data'] is! List) {
      throw FormatException('The API returned an invalid $name response.');
    }
    return (response['data'] as List)
        .map((item) => Booking.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  int _indexOf(String bookingId) {
    final index = _bookings.indexWhere((booking) => booking.id == bookingId);
    if (index == -1) throw Exception('Booking tidak ditemukan');
    return index;
  }
}

class BookingNotifier extends StateNotifier<List<Booking>> {
  final BookingRepository _repo;

  BookingNotifier(this._repo) : super(_repo.getAllBookings());

  void refresh() => state = _repo.getAllBookings();

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

final bookingRepositoryProvider = Provider<BookingRepository>(
  (ref) => BookingRepository(apiClient: ref.watch(apiClientProvider)),
);

final serverBookingProvider = FutureProvider.autoDispose.family<BookingHold, String>(
  (ref, bookingId) => ref.watch(bookingRepositoryProvider).fetchBookingById(bookingId),
);

final midwifeBookingsProvider = FutureProvider.autoDispose<List<Booking>>(
  (ref) => ref.watch(bookingRepositoryProvider).getMidwifeBookings(),
);

final patientHistoryProvider = FutureProvider.autoDispose<List<Booking>>(
  (ref) => ref.watch(bookingRepositoryProvider).getPatientHistory(),
);

final consultationResultProvider = FutureProvider.autoDispose.family<ConsultationResult?, String>(
  (ref, bookingId) => ref.watch(bookingRepositoryProvider).fetchConsultationResult(bookingId),
);

final bookingsListProvider = StateNotifierProvider<BookingNotifier, List<Booking>>(
  (ref) => BookingNotifier(ref.watch(bookingRepositoryProvider)),
);
