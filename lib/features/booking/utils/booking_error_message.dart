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
    return 'Server sedang bermasalah (HTTP $statusCode). Coba lagi beberapa saat.';
  }

  if (statusCode == 403) {
    return 'Akun ini tidak memiliki akses untuk membuat booking.';
  }

  if (statusCode == 422) {
    return 'Data booking ditolak server. Periksa keluhan dan slot, lalu coba lagi.';
  }

  if (statusCode == 429) {
    return 'Terlalu banyak percobaan booking. Tunggu sebentar lalu coba lagi.';
  }

  if (error.response == null) {
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        'Koneksi ke server timeout. Periksa jaringan dan pastikan backend berjalan.',
      _ =>
        'Tidak dapat terhubung ke server. Periksa jaringan dan alamat backend.',
    };
  }

  return 'Server menolak booking (HTTP $statusCode). Periksa data lalu coba lagi.';
}
