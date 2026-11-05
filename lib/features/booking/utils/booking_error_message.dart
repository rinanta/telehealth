import 'package:dio/dio.dart';

String bookingSubmissionErrorMessage(DioException error) {
  final statusCode = error.response?.statusCode;
  final responseBody = error.response?.data;
  final code = responseBody is Map ? responseBody['code'] : null;

  if (statusCode == 401 || code == 'unauthenticated') {
    return 'Sesi login berakhir. Silakan masuk kembali lalu coba booking.';
  }

  if (code == 'slot_unavailable') {
    return 'Slot sudah diambil atau tidak tersedia. Pilih jadwal lain.';
  }

  if (statusCode != null && statusCode >= 500) {
    return 'Layanan sedang bermasalah. Coba lagi beberapa saat.';
  }

  if (statusCode == 403) {
    return 'Akun ini tidak memiliki akses untuk membuat booking.';
  }

  if (statusCode == 422) {
    return 'Data booking tidak dapat diproses. Periksa keluhan dan slot, lalu coba lagi.';
  }

  if (statusCode == 429) {
    return 'Terlalu banyak percobaan booking. Tunggu sebentar lalu coba lagi.';
  }

  if (error.response == null) {
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        'Koneksi terlalu lama. Periksa jaringan lalu coba lagi.',
      _ =>
        'Tidak dapat terhubung. Periksa jaringan lalu coba lagi.',
    };
  }

  return 'Booking tidak dapat diproses. Periksa data lalu coba lagi.';
}
