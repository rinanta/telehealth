class ConsultationResult {
  final String id;
  final String consultationId;
  final String bookingId;
  final String patientName;
  final String midwifeName;
  final String summary;
  final String advice;
  final String? supplementNote;
  final String followUp;
  final String savedBy;
  final DateTime completedAt;

  const ConsultationResult({
    required this.id,
    required this.consultationId,
    required this.bookingId,
    required this.patientName,
    required this.midwifeName,
    required this.summary,
    required this.advice,
    this.supplementNote,
    required this.followUp,
    required this.savedBy,
    required this.completedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'consultation_id': consultationId,
    'booking_id': bookingId,
    'patient_name': patientName,
    'midwife_name': midwifeName,
    'summary': summary,
    'advice': advice,
    'supplement_note': supplementNote,
    'follow_up': followUp,
    'saved_by': savedBy,
    'completed_at': completedAt.toIso8601String(),
  };

  factory ConsultationResult.fromJson(Map<String, dynamic> json) => ConsultationResult(
    id: json['id'] as String,
    consultationId: json['consultation_id'] as String,
    bookingId: json['booking_id'] as String,
    patientName: json['patient_name'] as String? ?? 'Pasien',
    midwifeName: json['midwife_name'] as String? ?? 'Bidan',
    summary: json['summary'] as String,
    advice: json['advice'] as String,
    supplementNote: json['supplement_note'] as String?,
    followUp: json['follow_up'] as String,
    savedBy: json['saved_by'] as String,
    completedAt: DateTime.parse(json['completed_at'] as String),
  );
}
