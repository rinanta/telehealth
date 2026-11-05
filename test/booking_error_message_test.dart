import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telebunda_app/features/booking/utils/booking_error_message.dart';

void main() {
  group('bookingSubmissionErrorMessage', () {
    test('distinguishes a connection failure', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/bookings'),
        type: DioExceptionType.connectionError,
      );

      expect(
        bookingSubmissionErrorMessage(error),
        contains('Tidak dapat terhubung'),
      );
    });

    test('distinguishes an expired login', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/bookings'),
        response: Response(
          requestOptions: RequestOptions(path: '/bookings'),
          statusCode: 401,
        ),
      );

      expect(bookingSubmissionErrorMessage(error), contains('Sesi login'));
    });

    test('distinguishes an unavailable slot', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/bookings'),
        response: Response(
          requestOptions: RequestOptions(path: '/bookings'),
          statusCode: 409,
          data: {'code': 'slot_unavailable'},
        ),
      );

      expect(
        bookingSubmissionErrorMessage(error),
        contains('Slot sudah diambil'),
      );
    });

    test('distinguishes a server error', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/bookings'),
        response: Response(
          requestOptions: RequestOptions(path: '/bookings'),
          statusCode: 500,
        ),
      );

      expect(
        bookingSubmissionErrorMessage(error),
        contains('Layanan sedang bermasalah'),
      );
    });
  });
}
