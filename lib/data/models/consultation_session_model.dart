import 'booking_model.dart';
import 'chat_message_model.dart';

class ConsultationSession {
  final Booking booking;
  final List<ChatMessage> messages;
  final bool canSend;

  const ConsultationSession({
    required this.booking,
    required this.messages,
    required this.canSend,
  });

  factory ConsultationSession.fromJson(Map<String, dynamic> json) {
    final booking = json['booking'];
    final messages = json['messages'];
    if (booking is! Map || messages is! List) {
      throw const FormatException(
        'The API returned an invalid consultation session.',
      );
    }

    return ConsultationSession(
      booking: Booking.fromJson(Map<String, dynamic>.from(booking)),
      messages: messages
          .map(
            (message) => ChatMessage.fromJson(
              Map<String, dynamic>.from(message as Map),
            ),
          )
          .toList(),
      canSend: json['can_send'] == true,
    );
  }
}
