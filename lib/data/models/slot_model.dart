class ConsultationSlot {
  final String id;
  final String midwifeId;
  final DateTime startAt;
  final DateTime endAt;
  final String status; // 'available', 'held', 'booked'
  final String? holdBookingId;
  final DateTime? holdExpiresAt;

  const ConsultationSlot({
    required this.id,
    required this.midwifeId,
    required this.startAt,
    required this.endAt,
    this.status = 'available',
    this.holdBookingId,
    this.holdExpiresAt,
  });

  bool get isAvailable => status == 'available';

  Map<String, dynamic> toJson() => {
    'id': id,
    'midwife_id': midwifeId,
    'start_at': startAt.toIso8601String(),
    'end_at': endAt.toIso8601String(),
    'status': status,
    'hold_booking_id': holdBookingId,
    'hold_expires_at': holdExpiresAt?.toIso8601String(),
  };

  factory ConsultationSlot.fromJson(Map<String, dynamic> json) => ConsultationSlot(
    id: json['id'] as String,
    midwifeId: json['midwife_id'] as String,
    startAt: DateTime.parse(json['start_at'] as String),
    endAt: DateTime.parse(json['end_at'] as String),
    status: json['status'] as String? ?? 'available',
    holdBookingId: json['hold_booking_id'] as String?,
    holdExpiresAt: json['hold_expires_at'] != null ? DateTime.tryParse(json['hold_expires_at'] as String) : null,
  );
}
