class BookingHold {
  static const validStatuses = {
    'awaiting_payment',
    'payment_failed',
    'expired',
    'cancelled',
    'paid_pending_midwife',
    'rejected',
    'confirmed',
    'active',
    'completed',
    'no_show',
  };

  final String id;
  final String patientId;
  final String midwifeId;
  final String slotId;
  final DateTime slotStartAt;
  final int amount;
  final String status;
  final DateTime createdAt;
  final DateTime holdExpiresAt;

  const BookingHold({
    required this.id,
    required this.patientId,
    required this.midwifeId,
    required this.slotId,
    required this.slotStartAt,
    required this.amount,
    required this.status,
    required this.createdAt,
    required this.holdExpiresAt,
  });

  factory BookingHold.fromJson(Map<String, dynamic> json) {
    final amount = json['amount'];
    if (amount is! int || amount <= 0) {
      throw const FormatException(
        'The API returned an invalid booking amount.',
      );
    }

    final status = json['status'];
    if (status is! String || !validStatuses.contains(status)) {
      throw const FormatException(
        'The API returned an invalid booking status.',
      );
    }

    return BookingHold(
      id: _requiredString(json, 'id'),
      patientId: _requiredString(json, 'patient_id'),
      midwifeId: _requiredString(json, 'midwife_id'),
      slotId: _requiredString(json, 'slot_id'),
      slotStartAt: _requiredDateTime(json, 'slot_start_at'),
      amount: amount,
      status: status,
      createdAt: _requiredDateTime(json, 'created_at'),
      holdExpiresAt: _requiredDateTime(json, 'hold_expires_at'),
    );
  }

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.isEmpty) {
      throw FormatException('The API returned an invalid booking $key.');
    }
    return value;
  }

  static DateTime _requiredDateTime(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String) {
      throw FormatException('The API returned an invalid booking $key.');
    }

    final dateTime = DateTime.tryParse(value);
    if (dateTime == null) {
      throw FormatException('The API returned an invalid booking $key.');
    }

    return dateTime;
  }
}
