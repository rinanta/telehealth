import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telebunda_app/core/network/api_client.dart';
import 'package:telebunda_app/data/repositories/midwife_repository.dart';

void main() {
  group('Midwife self-management API', () {
    test('fetches midwife own profile and consultation fee', () async {
      final adapter = _JsonAdapter(200, {
        'data': {
          'uid': 'midwife-123',
          'display_name': 'Bidan Siti',
          'credential_label': 'BPM',
          'bio': 'Praktik mandiri.',
          'consultation_fee': 75000,
          'active': true,
          'verification_status': 'verified',
        },
      });
      final repo = _repository(adapter);

      final profile = await repo.getMyProfile();

      expect(adapter.requestOptions?.method, 'GET');
      expect(adapter.requestOptions?.path, '/midwife/profile');
      expect(profile.uid, 'midwife-123');
      expect(profile.name, 'Bidan Siti');
      expect(profile.price, 75000);
    });

    test('updates consultation fee via PATCH /midwife/profile', () async {
      final adapter = _JsonAdapter(200, {
        'data': {
          'uid': 'midwife-123',
          'display_name': 'Bidan Siti',
          'credential_label': 'BPM',
          'consultation_fee': 85000,
        },
      });
      final repo = _repository(adapter);

      final updated = await repo.updateMyProfile(consultationFee: 85000);

      expect(adapter.requestOptions?.method, 'PATCH');
      expect(adapter.requestOptions?.path, '/midwife/profile');
      expect(adapter.requestData, {'consultation_fee': 85000});
      expect(updated.price, 85000);
    });

    test('fetches midwife own slots list', () async {
      final adapter = _JsonAdapter(200, {
        'data': [
          {
            'id': 'slot-1',
            'midwife_id': 'midwife-123',
            'start_at': '2026-11-10T09:00:00Z',
            'end_at': '2026-11-10T09:30:00Z',
            'status': 'available',
          },
          {
            'id': 'slot-2',
            'midwife_id': 'midwife-123',
            'start_at': '2026-11-10T10:00:00Z',
            'end_at': '2026-11-10T10:30:00Z',
            'status': 'booked',
          },
        ],
      });
      final repo = _repository(adapter);

      final slots = await repo.getMySlots();

      expect(adapter.requestOptions?.method, 'GET');
      expect(adapter.requestOptions?.path, '/midwife/slots');
      expect(slots.length, 2);
      expect(slots[0].id, 'slot-1');
      expect(slots[0].isAvailable, true);
      expect(slots[1].id, 'slot-2');
      expect(slots[1].isAvailable, false);
    });

    test('creates new consultation slot with 30-min duration', () async {
      final startAt = DateTime.utc(2026, 11, 10, 9, 0);
      final adapter = _JsonAdapter(201, {
        'data': {
          'id': 'new-slot-id',
          'midwife_id': 'midwife-123',
          'start_at': startAt.toIso8601String(),
          'end_at': startAt.add(const Duration(minutes: 30)).toIso8601String(),
          'status': 'available',
        },
      });
      final repo = _repository(adapter);

      final slot = await repo.createSlot(startAt);

      expect(adapter.requestOptions?.method, 'POST');
      expect(adapter.requestOptions?.path, '/midwife/slots');
      expect(adapter.requestData, {
        'start_at': '2026-11-10T09:00:00.000Z',
      });
      expect(slot.id, 'new-slot-id');
      expect(slot.isAvailable, true);
    });

    test('deletes an available slot via DELETE /midwife/slots/{id}', () async {
      final adapter = _JsonAdapter(200, {
        'data': {'id': 'slot-1', 'deleted': true},
      });
      final repo = _repository(adapter);

      await repo.deleteSlot('slot-1');

      expect(adapter.requestOptions?.method, 'DELETE');
      expect(adapter.requestOptions?.path, '/midwife/slots/slot-1');
    });
  });
}

MidwifeRepository _repository(HttpClientAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://example.test/api'))..httpClientAdapter = adapter;
  return MidwifeRepository(ApiClient(customDio: dio));
}

class _JsonAdapter implements HttpClientAdapter {
  final int statusCode;
  final Map<String, dynamic> body;
  RequestOptions? requestOptions;

  _JsonAdapter(this.statusCode, this.body);

  dynamic get requestData => requestOptions?.data;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestOptions = options;
    return ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}
