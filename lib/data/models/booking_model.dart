class Booking {
  final String id;
  final String patientId;
  final String patientName;
  final String midwifeId;
  final String midwifeName;
  final String slotId;
  final DateTime slotStartAt;
  final String complaint;
  final int amount;
  final String status;
  // 'awaiting_payment', 'paid_pending_midwife', 'confirmed', 'active', 'completed', 'rejected', 'expired'
  final String? paymentId;
  final String? checkoutUrl;
  final String? rejectionReason;
  final DateTime? consultationStartedAt;
  final DateTime? endsAt;
  final DateTime? consultationCompletedAt;
  final DateTime createdAt;

  const Booking({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.midwifeId,
    required this.midwifeName,
    required this.slotId,
    required this.slotStartAt,
    required this.complaint,
    required this.amount,
    required this.status,
    this.paymentId,
    this.checkoutUrl,
    this.rejectionReason,
    this.consultationStartedAt,
    this.endsAt,
    this.consultationCompletedAt,
    required this.createdAt,
  });

  bool get isAwaitingPayment => status == 'awaiting_payment';
  bool get isPaidPendingMidwife => status == 'paid_pending_midwife';
  bool get isConfirmed => status == 'confirmed';
  bool get isActive => status == 'active';

  /// Sesi tetap berstatus `active` sampai bidan menyimpan hasil, tetapi chat
  /// hanya aktif hingga `ends_at` yang ditetapkan server.
  bool get isChatActive {
    if (!isActive) return false;
    final expiresAt = endsAt ?? consultationStartedAt?.add(const Duration(minutes: 30));
    return expiresAt?.isAfter(DateTime.now()) ?? false;
  }

  bool get isAwaitingResult => isActive && !isChatActive;
  bool get isCompleted => status == 'completed';
  bool get isRejected => status == 'rejected';
  bool get isNoShow => status == 'no_show';

  String get statusLabel {
    switch (status) {
      case 'awaiting_payment':
        return 'Menunggu Pembayaran';
      case 'paid_pending_midwife':
        return 'Menunggu Konfirmasi Bidan';
      case 'confirmed':
        return 'Jadwal Terkonfirmasi';
      case 'active':
        return 'Sesi Konsultasi Berlangsung';
      case 'completed':
        return 'Selesai';
      case 'rejected':
        return 'Ditolak';
      case 'no_show':
        return 'Tidak Hadir';
      case 'expired':
        return 'Kedaluwarsa';
      default:
        return status;
    }
  }

  Booking copyWith({
    String? id,
    String? patientId,
    String? patientName,
    String? midwifeId,
    String? midwifeName,
    String? slotId,
    DateTime? slotStartAt,
    String? complaint,
    int? amount,
    String? status,
    String? paymentId,
    String? checkoutUrl,
    String? rejectionReason,
    DateTime? consultationStartedAt,
    DateTime? endsAt,
    DateTime? consultationCompletedAt,
    DateTime? createdAt,
  }) {
    return Booking(
      id: id ?? this.id,
      patientId: patientId ?? this.patientId,
      patientName: patientName ?? this.patientName,
      midwifeId: midwifeId ?? this.midwifeId,
      midwifeName: midwifeName ?? this.midwifeName,
      slotId: slotId ?? this.slotId,
      slotStartAt: slotStartAt ?? this.slotStartAt,
      complaint: complaint ?? this.complaint,
      amount: amount ?? this.amount,
      status: status ?? this.status,
      paymentId: paymentId ?? this.paymentId,
      checkoutUrl: checkoutUrl ?? this.checkoutUrl,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      consultationStartedAt: consultationStartedAt ?? this.consultationStartedAt,
      endsAt: endsAt ?? this.endsAt,
      consultationCompletedAt: consultationCompletedAt ?? this.consultationCompletedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'patient_id': patientId,
    'patient_name': patientName,
    'midwife_id': midwifeId,
    'midwife_name': midwifeName,
    'slot_id': slotId,
    'slot_start_at': slotStartAt.toIso8601String(),
    'complaint': complaint,
    'amount': amount,
    'status': status,
    'payment_id': paymentId,
    'checkout_url': checkoutUrl,
    'rejection_reason': rejectionReason,
    'consultation_started_at': consultationStartedAt?.toIso8601String(),
    'ends_at': endsAt?.toIso8601String(),
    'consultation_completed_at': consultationCompletedAt?.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
  };

  factory Booking.fromJson(Map<String, dynamic> json) => Booking(
    id: json['id'] as String,
    patientId: json['patient_id'] as String,
    patientName: json['patient_name'] as String,
    midwifeId: json['midwife_id'] as String,
    midwifeName: json['midwife_name'] as String,
    slotId: json['slot_id'] as String,
    slotStartAt: DateTime.parse(json['slot_start_at'] as String),
    complaint: json['complaint'] as String,
    amount: json['amount'] as int? ?? 50000,
    status: json['status'] as String,
    paymentId: json['payment_id'] as String?,
    checkoutUrl: json['checkout_url'] as String?,
    rejectionReason: json['rejection_reason'] as String?,
    consultationStartedAt: json['consultation_started_at'] != null ? DateTime.tryParse(json['consultation_started_at'] as String) : null,
    endsAt: json['ends_at'] != null ? DateTime.tryParse(json['ends_at'] as String) : null,
    consultationCompletedAt: json['consultation_completed_at'] != null ? DateTime.tryParse(json['consultation_completed_at'] as String) : null,
    createdAt: DateTime.parse(json['created_at'] as String),
  );
}
