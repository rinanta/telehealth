import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telebunda_app/core/network/api_client.dart';
import 'package:telebunda_app/data/repositories/booking_repository.dart';

void main() {
  group('Consultation result API', () {
    test('posts the result sheet and omits an empty supplement note', () async {
      final adapter = _JsonAdapter(200, {
        'data': {'id': 'booking-123', 'status': 'completed'},
      });
      final repository = _repository(adapter);

      await repository.completeMidwifeConsultation(
        bookingId: 'booking-123',
        summary: 'Ringkasan temuan.',
        advice: 'Saran perawatan.',
        supplementNote: '   ',
        followUp: 'Kontrol ANC.',
      );

      expect(adapter.requestOptions?.method, 'POST');
      expect(adapter.requestOptions?.path, '/bookings/booking-123/complete');
      expect(adapter.requestData, {
        'summary': 'Ringkasan temuan.',
        'advice': 'Saran perawatan.',
        'follow_up': 'Kontrol ANC.',
      });
    });

    test('sends the supplement note when the midwife filled it in', () async {
      final adapter = _JsonAdapter(200, {'data': {}});
      final repository = _repository(adapter);

      await repository.completeMidwifeConsultation(
        bookingId: 'booking-123',
        summary: 'Ringkasan temuan.',
        advice: 'Saran perawatan.',
        supplementNote: ' Tablet Fe 1x1 ',
        followUp: 'Kontrol ANC.',
      );

      expect(adapter.requestData['supplement_note'], 'Tablet Fe 1x1');
    });

    test('fetches and parses a saved consultation result', () async {
      final adapter = _JsonAdapter(200, {
        'data': {
          'id': 'booking-123',
          'consultation_id': 'booking-123',
          'booking_id': 'booking-123',
          'patient_name': 'Bunda Pasien',
          'midwife_name': 'Bidan Terverifikasi',
          'summary': 'Ringkasan.',
          'advice': 'Saran.',
          'supplement_note': null,
          'follow_up': 'Kontrol.',
          'saved_by': 'Bidan Terverifikasi',
          'completed_at': '2026-11-04T05:00:00Z',
        },
      });
      final repository = _repository(adapter);

      final result = await repository.fetchConsultationResult('booking-123');

      expect(adapter.requestOptions?.path, '/bookings/booking-123/result');
      expect(result?.summary, 'Ringkasan.');
      expect(result?.supplementNote, isNull);
      expect(result?.completedAt, DateTime.parse('2026-11-04T05:00:00Z'));
    });

    test('returns null while the midwife has not saved a result yet', () async {
      final repository = _repository(
        _JsonAdapter(404, {'message': 'Not ready.', 'code': 'result_not_found'}),
      );

      expect(await repository.fetchConsultationResult('booking-123'), isNull);
    });

    test('rethrows other errors instead of hiding them as "no result"', () async {
      final repository = _repository(
        _JsonAdapter(404, {'message': 'Nope.', 'code': 'booking_not_found'}),
      );

      await expectLater(
        repository.fetchConsultationResult('booking-123'),
        throwsA(isA<DioException>()),
      );
    });

    test('loads the patient history from the server', () async {
      final adapter = _JsonAdapter(200, {
        'data': [
          {
            'id': 'booking-123',
            'patient_id': 'patient-123',
            'patient_name': 'Bunda Pasien',
            'midwife_id': 'midwife-123',
            'midwife_name': 'Bidan Terverifikasi',
            'slot_id': 'slot-123',
            'slot_start_at': '2026-11-04T04:00:00Z',
            'complaint': 'Pusing.',
            'amount': 75000,
            'status': 'completed',
            'created_at': '2026-11-04T03:00:00Z',
          },
        ],
      });
      final repository = _repository(adapter);

      final history = await repository.getPatientHistory();

      expect(adapter.requestOptions?.method, 'GET');
      expect(adapter.requestOptions?.path, '/history');
      expect(history, hasLength(1));
      expect(history.single.isCompleted, isTrue);
      expect(history.single.midwifeName, 'Bidan Terverifikasi');
    });

    test('rejects a malformed history response', () async {
      final repository = _repository(_JsonAdapter(200, {'data': 'oops'}));

      await expectLater(
        repository.getPatientHistory(),
        throwsFormatException,
      );
    });
  });
}

BookingRepository _repository(_JsonAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'));
  dio.httpClientAdapter = adapter;
  final apiClient = ApiClient(customDio: dio)
    ..setTokenProvider(() async => 'firebase-id-token');
  return BookingRepository(apiClient: apiClient);
}

class _JsonAdapter implements HttpClientAdapter {
  final int statusCode;
  final Map<String, dynamic> response;
  RequestOptions? requestOptions;
  dynamic requestData;

  _JsonAdapter(this.statusCode, this.response);

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
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
