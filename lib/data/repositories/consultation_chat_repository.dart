import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/chat_message_model.dart';

class ConsultationChatRepository {
  final _uuid = const Uuid();
  final Map<String, List<ChatMessage>> _chats = {};

  ConsultationChatRepository() {
    _seedChat();
  }

  void _seedChat() {
    final now = DateTime.now();
    _chats['book_history_001'] = [
      ChatMessage(
        id: 'msg_01',
        senderId: 'patient_001',
        senderName: 'Bunda Anisa Lestari',
        text: 'Selamat siang Bidan Siti, belakangan ini saya sering merasa pusing saat bangun tidur dan perut bagian bawah terasa kencang sedikit.',
        sentAt: now.subtract(const Duration(days: 3, minutes: 28)),
        isMidwife: false,
      ),
      ChatMessage(
        id: 'msg_02',
        senderId: 'midwife_001',
        senderName: 'Bdn. Siti Rahmawati, S.Tr.Keb',
        text: 'Selamat siang Bunda Anisa. Terima kasih sudah berbagi. Keluhan pusing saat bangun posisi tidur ke berdiri sering kali dipicu tekanan darah yang belum stabil atau dehidrasi ringan (hipotensi ortostatik). Apakah Bunda mencukupi air putih 2.5 liter per hari?',
        sentAt: now.subtract(const Duration(days: 3, minutes: 25)),
        isMidwife: true,
      ),
      ChatMessage(
        id: 'msg_03',
        senderId: 'patient_001',
        senderName: 'Bunda Anisa Lestari',
        text: 'Iya Bidan, kadang saya suka lupa minum kalau sedang sibuk. Kramnya juga biasanya muncul kalau saya berjalan agak cepat.',
        sentAt: now.subtract(const Duration(days: 3, minutes: 20)),
        isMidwife: false,
      ),
      ChatMessage(
        id: 'msg_04',
        senderId: 'midwife_001',
        senderName: 'Bdn. Siti Rahmawati, S.Tr.Keb',
        text: 'Baik Bunda, kram tersebut fisiologis akibat peregangan ligamen penopang rahim (round ligament pain). Saya akan rangkum saran dan suplemen yang perlu dilanjutkan pada lembar hasil ya.',
        sentAt: now.subtract(const Duration(days: 3, minutes: 12)),
        isMidwife: true,
      ),
    ];
  }

  List<ChatMessage> getMessages(String bookingId) {
    return _chats[bookingId] ?? [];
  }

  Future<ChatMessage> sendMessage({
    required String bookingId,
    required String senderId,
    required String senderName,
    required String text,
    required bool isMidwife,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));

    final msg = ChatMessage(
      id: 'msg_${_uuid.v4().substring(0, 8)}',
      senderId: senderId,
      senderName: senderName,
      text: text,
      sentAt: DateTime.now(),
      isMidwife: isMidwife,
    );

    if (!_chats.containsKey(bookingId)) {
      _chats[bookingId] = [];
    }
    _chats[bookingId]!.add(msg);
    return msg;
  }
}

class ConsultationChatNotifier extends StateNotifier<Map<String, List<ChatMessage>>> {
  final ConsultationChatRepository _repo;

  ConsultationChatNotifier(this._repo) : super({'book_history_001': _repo.getMessages('book_history_001')});

  List<ChatMessage> getMessagesFor(String bookingId) {
    return state[bookingId] ?? _repo.getMessages(bookingId);
  }

  Future<void> sendMessage({
    required String bookingId,
    required String senderId,
    required String senderName,
    required String text,
    required bool isMidwife,
  }) async {
    final msg = await _repo.sendMessage(
      bookingId: bookingId,
      senderId: senderId,
      senderName: senderName,
      text: text,
      isMidwife: isMidwife,
    );

    final currentList = List<ChatMessage>.from(state[bookingId] ?? []);
    currentList.add(msg);

    state = {
      ...state,
      bookingId: currentList,
    };
  }
}

final consultationChatRepositoryProvider = Provider<ConsultationChatRepository>((ref) => ConsultationChatRepository());

final consultationChatProvider = StateNotifierProvider<ConsultationChatNotifier, Map<String, List<ChatMessage>>>((ref) {
  final repo = ref.watch(consultationChatRepositoryProvider);
  return ConsultationChatNotifier(repo);
});
