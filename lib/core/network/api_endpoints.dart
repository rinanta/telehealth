/// Kontrak rute endpoint REST API Laravel TeleBunda AI (Sesuai PRD Bab 9)
class ApiEndpoints {
  // Base URL konfigurasi lingkungan DEV/STAGING
  static const String baseUrl = 'http://10.0.2.2:8000/api'; // 10.0.2.2 untuk emulator Android

  // Auth & Profile
  static const String register = '/auth/register';
  static const String me = '/me';

  // Midwife & Slots
  static const String midwives = '/midwives';
  static String midwifeSlots(String midwifeId) => '/midwives/$midwifeId/slots';

  // Bookings & Payments
  static const String bookings = '/bookings';
  static String bookingCheckout(String bookingId) => '/bookings/$bookingId/checkout';
  static String bookingAccept(String bookingId) => '/bookings/$bookingId/accept';
  static String bookingReject(String bookingId) => '/bookings/$bookingId/reject';

  // Consultations & Live Sessions
  static String consultationStart(String id) => '/consultations/$id/start';
  static String consultationDetail(String id) => '/consultations/$id';
  static String consultationComplete(String id) => '/consultations/$id/complete';

  // Gemini AI Chat
  static const String aiChat = '/ai/chat';

  // Medical History
  static const String history = '/history';
}
