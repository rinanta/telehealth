class ChatMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String text;
  final DateTime sentAt;
  final bool isMidwife;
  final bool isAi;

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.sentAt,
    this.isMidwife = false,
    this.isAi = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'sender_id': senderId,
    'sender_name': senderName,
    'text': text,
    'sent_at': sentAt.toIso8601String(),
    'is_midwife': isMidwife,
    'is_ai': isAi,
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as String,
    senderId: json['sender_id'] as String,
    senderName: json['sender_name'] as String,
    text: json['text'] as String,
    sentAt: DateTime.parse(json['sent_at'] as String),
    isMidwife: json['is_midwife'] as bool? ?? false,
    isAi: json['is_ai'] as bool? ?? false,
  );
}
