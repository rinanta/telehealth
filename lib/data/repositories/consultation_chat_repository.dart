import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../models/chat_message_model.dart';
import '../models/consultation_session_model.dart';

class ConsultationChatRepository {
  final ApiClient _apiClient;

  ConsultationChatRepository(this._apiClient);

  Future<ConsultationSession> getSession(String bookingId) async {
    final response = await _apiClient.get(
      ApiEndpoints.bookingMessages(bookingId),
    );
    final payload = response.data;
    if (payload is! Map || payload['data'] is! Map) {
      throw const FormatException(
        'The API returned an invalid consultation response.',
      );
    }

    return ConsultationSession.fromJson(
      Map<String, dynamic>.from(payload['data'] as Map),
    );
  }

  Future<ChatMessage> sendMessage({
    required String bookingId,
    required String text,
  }) async {
    final response = await _apiClient.post(
      ApiEndpoints.bookingMessages(bookingId),
      data: {'text': text},
    );
    final payload = response.data;
    if (payload is! Map || payload['data'] is! Map) {
      throw const FormatException(
        'The API returned an invalid chat message response.',
      );
    }

    return ChatMessage.fromJson(
      Map<String, dynamic>.from(payload['data'] as Map),
    );
  }
}

final consultationChatRepositoryProvider = Provider<ConsultationChatRepository>(
  (ref) => ConsultationChatRepository(ref.watch(apiClientProvider)),
);

final consultationSessionProvider = FutureProvider.autoDispose.family<ConsultationSession, String>(
  (ref, bookingId) => ref.watch(consultationChatRepositoryProvider).getSession(bookingId),
);
