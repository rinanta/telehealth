import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telebunda_app/core/network/api_client.dart';
import 'package:telebunda_app/data/models/slot_model.dart';
import 'package:telebunda_app/data/repositories/booking_repository.dart';

void main() {
  group('Booking API', () {
    test(
      'posts the selected slot with Firebase token and uses server amount',
      () async {
        final adapter = _BookingHttpClientAdapter(
          _bookingResponse(amount: 82500),
        );
        final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'));
        dio.httpClientAdapter = adapter;
        final apiClient = ApiClient(customDio: dio)
          ..setTokenProvider(() async => 'firebase-id-token');
        final repository = BookingRepository(apiClient: apiClient);

        final booking = await repository.createBookingRequest(
          slot: ConsultationSlot(
            id: 'slot-123',
            midwifeId: 'midwife-123',
            startAt: DateTime.utc(2026, 11, 5, 10),
            endAt: DateTime.utc(2026, 11, 5, 10, 30),
          ),
          complaint: 'Keluhan singkat.',
        );

        expect(booking.amount, 82500);
        expect(booking.status, 'awaiting_payment');
        expect(booking.holdExpiresAt, DateTime.parse('2026-11-04T04:15:00Z'));
        expect(adapter.requestOptions?.method, 'POST');
        expect(adapter.requestOptions?.path, '/bookings');
        expect(
          adapter.requestOptions?.headers['Authorization'],
          'Bearer firebase-id-token',
        );
        expect(adapter.requestData, {
          'slot_id': 'slot-123',
          'complaint': 'Keluhan singkat.',
        });
      },
    );

    test(
      'fetches the latest booking status from its protected endpoint',
      () async {
        final response = _bookingResponse(amount: 82500)
          ..['data']['status'] = 'paid_pending_midwife';
        final adapter = _BookingHttpClientAdapter(response);
        final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'));
        dio.httpClientAdapter = adapter;
        final apiClient = ApiClient(customDio: dio)
          ..setTokenProvider(() async => 'firebase-id-token');
        final repository = BookingRepository(apiClient: apiClient);

        final booking = await repository.fetchBookingById('booking-123');

        expect(booking.status, 'paid_pending_midwife');
        expect(adapter.requestOptions?.method, 'GET');
        expect(adapter.requestOptions?.path, '/bookings/booking-123');
        expect(
          adapter.requestOptions?.headers['Authorization'],
          'Bearer firebase-id-token',
        );
      },
    );

    test('rejects a booking response that omits its server amount', () async {
      final response = _bookingResponse(amount: null);
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'));
      dio.httpClientAdapter = _BookingHttpClientAdapter(response);
      final repository = BookingRepository(
        apiClient: ApiClient(customDio: dio),
      );

      await expectLater(
        repository.createBookingRequest(
          slot: ConsultationSlot(
            id: 'slot-123',
            midwifeId: 'midwife-123',
            startAt: DateTime.utc(2026, 11, 5, 10),
            endAt: DateTime.utc(2026, 11, 5, 10, 30),
          ),
          complaint: 'Keluhan singkat.',
        ),
        throwsFormatException,
      );
    });
  });
}

Map<String, dynamic> _bookingResponse({required int? amount}) {
  final data = <String, dynamic>{
    'id': 'booking-123',
    'patient_id': 'patient-123',
    'midwife_id': 'midwife-123',
    'slot_id': 'slot-123',
    'slot_start_at': '2026-11-05T10:00:00Z',
    'status': 'awaiting_payment',
    'created_at': '2026-11-04T04:00:00Z',
    'hold_expires_at': '2026-11-04T04:15:00Z',
  };
  if (amount != null) data['amount'] = amount;
  return {'data': data};
}

class _BookingHttpClientAdapter implements HttpClientAdapter {
  final Map<String, dynamic> response;
  RequestOptions? requestOptions;
  dynamic requestData;

  _BookingHttpClientAdapter(this.response);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestOptions = options;
    final data = options.data;
    requestData = data is String ? jsonDecode(data) : data;
    return ResponseBody.fromString(
      jsonEncode(response),
      HttpStatus.created,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
