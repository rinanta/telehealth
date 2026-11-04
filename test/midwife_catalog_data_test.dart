import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telebunda_app/core/network/api_client.dart';
import 'package:telebunda_app/data/models/midwife_model.dart';
import 'package:telebunda_app/data/repositories/midwife_repository.dart';

void main() {
  group('Midwife catalog data', () {
    test('uses the API response rather than local catalog fixtures', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'));
      dio.httpClientAdapter = _FakeHttpClientAdapter({
        'data': [
          {
            'uid': 'midwife-123',
            'display_name': 'Bidan API',
            'credential_label': 'Bidan',
          },
        ],
      });
      final repository = MidwifeRepository(ApiClient(customDio: dio));

      final midwives = await repository.getMidwives();

      expect(midwives, hasLength(1));
      expect(midwives.single.uid, 'midwife-123');
      expect(midwives.single.name, 'Bidan API');
    });

    test(
      'does not invent optional profile values when API fields are absent',
      () {
        final midwife = Midwife.fromJson({
          'uid': 'midwife-123',
          'display_name': 'Bidan Terverifikasi',
          'credential_label': 'Bidan',
        });

        expect(midwife.rating, isNull);
        expect(midwife.reviewCount, isNull);
        expect(midwife.experienceYears, isNull);
        expect(midwife.price, isNull);
        expect(midwife.strNumber, isNull);
        expect(midwife.hospitalAffiliation, isNull);
      },
    );
  });
}

class _FakeHttpClientAdapter implements HttpClientAdapter {
  final Map<String, dynamic> response;

  _FakeHttpClientAdapter(this.response);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode(response),
      HttpStatus.ok,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
