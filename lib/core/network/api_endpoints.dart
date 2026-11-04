/// Kontrak rute endpoint REST API Laravel TeleBunda AI (Sesuai PRD Bab 9)
class ApiEndpoints {
  // Default memakai tunnel HTTPS dev yang sedang aktif.
  // Override dengan --dart-define=API_BASE_URL=... bila URL tunnel berubah.
  // Lokal emulator: http://10.0.2.2:8000/api
  // Perangkat fisik di LAN: gunakan IP komputer yang menjalankan Laravel.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://unaccessible-kori-administratively.ngrok-free.dev/api',
  );

  // Auth & Profile
  static const String register = '/auth/register';
  static const String me = '/me';

  // Midwife & Slots
  static const String midwives = '/midwives';
  static String midwifeSlots(String midwifeId) => '/midwives/$midwifeId/slots';

  // Midwife Self Management (Tarif & Jadwal)
  static const String midwifeProfile = '/midwife/profile';
  static const String midwifeOwnSlots = '/midwife/slots';
  static String midwifeOwnSlot(String slotId) => '/midwife/slots/$slotId';

  // Bookings & Payments
  static const String bookings = '/bookings';
  static String booking(String bookingId) => '/bookings/$bookingId';
  static String bookingMessages(String bookingId) =>
      '/bookings/$bookingId/messages';
  static String bookingCheckout(String bookingId) =>
      '/bookings/$bookingId/checkout';
  static String bookingAccept(String bookingId) =>
      '/bookings/$bookingId/accept';
  static String bookingReject(String bookingId) =>
      '/bookings/$bookingId/reject';
  static const String midwifeBookings = '/midwife/bookings';
  static String midwifeBookingAccept(String bookingId) =>
      bookingAccept(bookingId);
  static String midwifeBookingReject(String bookingId) =>
      bookingReject(bookingId);
  static String midwifeBookingStart(String bookingId) =>
      '/bookings/$bookingId/start';
  static String midwifeBookingComplete(String bookingId) =>
      '/bookings/$bookingId/complete';
  static String bookingResult(String bookingId) =>
      '/bookings/$bookingId/result';

  // Consultations & Live Sessions
  static String consultationStart(String id) => '/consultations/$id/start';
  static String consultationDetail(String id) => '/consultations/$id';
  static String consultationComplete(String id) =>
      '/consultations/$id/complete';

  // Gemini AI Chat
  static const String aiChat = '/ai/chat';

  // Medical History
  static const String history = '/history';
}
