import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../models/chat_message_model.dart';

class AiChatRepository {
  final ApiClient? _apiClient;
  final _uuid = const Uuid();

  AiChatRepository([this._apiClient]);

  // Memeriksa tanda bahaya (red flag obstetric)
  bool _isRedFlag(String message) {
    final lower = message.toLowerCase();
    return lower.contains('darah') ||
        lower.contains('pendarahan') ||
        lower.contains('perdarahan') ||
        lower.contains('ketuban pecah') ||
        lower.contains('rembes') ||
        lower.contains('kejang') ||
        lower.contains('pandangan kabur') ||
        lower.contains('tidak bergerak') ||
        lower.contains('janin diam') ||
        lower.contains('nyeri dada');
  }

  Future<ChatMessage> askGemini(
    String userMessage, {
    List<Map<String, String>> history = const [],
  }) async {
    // 1. Lapisan Keselamatan Red-Flag Klien (Instan, Tanpa Menunggu Jaringan)
    if (_isRedFlag(userMessage)) {
      return _createMessage(_emergencyReply());
    }

    // 2. Pemanggilan API Server-Side Gemini (Jika ApiClient Tersedia)
    final client = _apiClient;
    if (client != null) {
      try {
        final response = await client.post(
          ApiEndpoints.aiChat,
          data: {
            'message': userMessage,
            if (history.isNotEmpty) 'history': history,
          },
        );

        final reply = response.data is Map && response.data['data'] is Map
            ? response.data['data']['reply'] as String?
            : null;

        if (reply != null && reply.trim().isNotEmpty) {
          return _createMessage(reply.trim());
        }
      } on DioException catch (e) {
        debugPrint('TeleBunda AI Backend Error: ${e.response?.statusCode} - ${e.message}');
        final serverMessage = e.response?.data is Map && e.response?.data['message'] is String
            ? e.response?.data['message'] as String
            : null;

        return _createMessage(
          serverMessage ??
              'Maaf Bunda, tidak dapat terhubung ke server AI TeleBunda (${e.message ?? 'Koneksi gagal'}). '
              'Pastikan server backend Laravel berjalan di ${ApiEndpoints.baseUrl} dan perangkat terhubung ke jaringan yang sama. '
              'Bunda juga dapat menjadwalkan konsultasi langsung dengan Bidan.',
        );
      } catch (e) {
        debugPrint('TeleBunda AI Error: $e');
        return _createMessage(
          'Maaf Bunda, terjadi kendala saat memproses jawaban AI ($e). Silakan coba lagi atau konsultasikan dengan Bidan.',
        );
      }
    }

    // 3. Fallback Edukasi Maternal Offline (Untuk Pengujian Unit / Dev Tanpa Network)
    return _createMessage(_localEducationReply(userMessage));
  }

  ChatMessage _createMessage(String text) => ChatMessage(
        id: 'ai_${_uuid.v4()}',
        senderId: 'gemini_ai',
        senderName: 'TeleBunda AI',
        text: text,
        sentAt: DateTime.now(),
        isAi: true,
      );

  String _emergencyReply() =>
      '⚠️ **PERINGATAN TANDA BAHAYA KEHAMILAN (RED FLAG)**:\n\n'
      'Gejala yang Bunda sebutkan berpotensi merupakan tanda kegawatdaruratan maternal/janin yang memerlukan evaluasi klinis langsung.\n\n'
      '🚨 **Tindakan yang harus segera diambil**:\n'
      '1. Jangan menunda, segera datangi IGD Rumah Sakit atau Puskesmas 24 Jam terdekat bersama pendamping.\n'
      '2. Hindari aktivitas berat, berbaringlah miring ke kiri jika memungkinkan.\n'
      '3. Bawa Buku KIA (Kesehatan Ibu dan Anak) serta riwayat pemeriksaan sebelumnya.\n\n'
      'AI TeleBunda tidak dapat menggantikan pemeriksaan medis darurat.';

  String _localEducationReply(String userMessage) {
    final lower = userMessage.toLowerCase();
    if (lower.contains('mual') || lower.contains('morning sickness')) {
      return 'Halo Bunda! Mual muntah (morning sickness) sangat umum terjadi pada trimester pertama karena lonjakan hormon hCG dan estrogen.\n\n'
          '💡 **Tips Alami Meredakan Mual**:\n'
          '• Makan porsi kecil tetapi sering (5-6 kali sehari).\n'
          '• Konsumsi biskuit/crackers kering sesaat setelah bangun tidur sebelum beranjak dari tempat tidur.\n'
          '• Minum air jahe hangat atau teh chamomile.\n'
          '• Hindari aroma tajam, makanan terlalu berlemak, atau terlalu pedas.\n\n'
          'Jika Bunda tidak bisa makan/minum sama sekali lebih dari 24 jam, sangat disarankan berkonsultasi langsung dengan Bidan di TeleBunda.';
    } else if (lower.contains('gerak') || lower.contains('tendangan')) {
      return 'Gerakan janin umumnya mulai dirasakan bunda pada usia kehamilan 18–22 minggu (quickening).\n\n'
          '💡 **Panduan Menghitung Tendangan Janin (Kick Counter)**:\n'
          '• Pilih waktu di mana janin biasanya aktif (biasanya malam hari atau setelah makan).\n'
          '• Standar sehat adalah minimal 10 gerakan dalam waktu 2 jam saat Bunda berbaring santai.\n\n'
          'Bila gerakan berkurang drastis atau tidak terasa sama sekali seharian, segera periksakan ke bidan atau dokter kandungan terdekat.';
    } else if (lower.contains('makanan') ||
        lower.contains('nutrisi') ||
        lower.contains('buah')) {
      return 'Asupan nutrisi yang seimbang sangat krusial bagi tumbuh kembang janin dan kesehatan Bunda!\n\n'
          '🥗 **Nutrisi Utama Ibu Hamil**:\n'
          '• **Asam Folat**: Sayuran hijau, jeruk, alpukat, dan kacang-kacangan.\n'
          '• **Zat Besi (Fe)**: Daging tanpa lemak, bayam, hati ayam (secukupnya) untuk mencegah anemia.\n'
          '• **Kalsium**: Susu pasteurisasi, keju, yoghurt, tahu/tempe.\n'
          '• **DHA & Omega-3**: Ikan matang sempurna (salmon, kembung).\n\n'
          'Pastikan semua makanan dicuci bersih dan dimasak matang. Untuk evaluasi status gizi personal, Bunda bisa jadwalkan Konsultasi Bidan di TeleBunda.';
    } else if (lower.contains('lahir') ||
        lower.contains('melahirkan') ||
        lower.contains('salin') ||
        lower.contains('persalinan') ||
        lower.contains('kontraksi') ||
        lower.contains('bukaan')) {
      return 'Halo Bunda! Menjelang persalinan, sangat penting untuk mengenali tanda-tanda tubuh bahwa Si Kecil siap lahir:\n\n'
          '👶 **Tanda Utama Persalinan**:\n'
          '• **Kontraksi teratur & kuat**: Terjadi setiap 5-10 menit dan semakin intens serta sering.\n'
          '• **Keluar lendir bercampur darah** (*bloody show*) dari jalan lahir.\n'
          '• **Air ketuban merembes atau pecah**.\n\n'
          '📋 **Persiapan Menuju Persalinan**:\n'
          '1. Siapkan tas bersalin berisi perlengkapan ibu & bayi serta dokumen penting (Buku KIA, KTP, BPJS).\n'
          '2. Tentukan fasilitas kesehatan dan bidan/dokter yang akan mendampingi.\n'
          '3. Latih teknik pernapasan untuk membantu meredakan nyeri saat kontraksi.\n\n'
          'Jika kontraksi sudah teratur setiap 5 menit atau keluar cairan ketuban, segera hubungi Bidan atau datangi fasilitas bersalin terdekat ya, Bunda.';
    } else {
      return 'Terima kasih telah bertanya kepada TeleBunda AI! 🌸\n\n'
          'Menjaga kehamilan yang sehat memerlukan perhatian pada asupan gizi seimbang, istirahat cukup, hidrasi minimal 2-2.5 liter per hari, dan pemeriksaan ANC rutin minimal 6 kali selama kehamilan.\n\n'
          'Perlu diingat bahwa jawaban AI ini bersifat edukatif. Untuk pemeriksaan mendalam dan penilaian klinis yang akurat, Bunda dapat menjadwalkan konsultasi chat langsung dengan Bidan berizin resmi melalui tombol di bawah.';
    }
  }
}

class AiChatNotifier extends StateNotifier<List<ChatMessage>> {
  final AiChatRepository _repo;
  final _uuid = const Uuid();
  bool _isLoading = false;

  bool get isLoading => _isLoading;

  AiChatNotifier(this._repo)
      : super([
          ChatMessage(
            id: 'welcome_ai',
            senderId: 'gemini_ai',
            senderName: 'TeleBunda AI',
            text:
                'Halo Bunda! Saya asisten edukasi kehamilan TeleBunda AI. 🌸\n\n'
                'Bunda bisa bertanya seputar perkembangan janin, tips nutrisi, cara mengatasi ketidaknyamanan kehamilan, atau persiapan persalinan.\n\n'
                '*(Informasi ini bersifat edukatif dan bukan diagnosis medis)*',
            sentAt: DateTime.now(),
            isAi: true,
          ),
        ]);

  Future<void> sendMessage(String text) async {
    final userMsg = ChatMessage(
      id: 'usr_${DateTime.now().millisecondsSinceEpoch}',
      senderId: 'current_user',
      senderName: 'Bunda',
      text: text,
      sentAt: DateTime.now(),
      isAi: false,
    );

    final history = state
        .where((m) => m.id != 'welcome_ai')
        .map((m) => {
              'role': m.isAi ? 'model' : 'user',
              'text': m.text,
            })
        .toList();

    state = [...state, userMsg];
    _isLoading = true;

    try {
      final aiReply = await _repo.askGemini(text, history: history);
      state = [...state, aiReply];
    } catch (_) {
      state = [
        ...state,
        ChatMessage(
          id: 'ai_error_${_uuid.v4()}',
          senderId: 'gemini_ai',
          senderName: 'TeleBunda AI',
          text:
              'Asisten AI sementara tidak dapat menjawab. Bunda dapat mencoba lagi atau menjadwalkan konsultasi dengan Bidan.',
          sentAt: DateTime.now(),
          isAi: true,
        ),
      ];
    } finally {
      _isLoading = false;
    }
  }

  void reset() {
    state = [
      ChatMessage(
        id: 'welcome_ai',
        senderId: 'gemini_ai',
        senderName: 'TeleBunda AI',
        text:
            'Halo Bunda! Ada yang bisa saya bantu terkait kehamilan Bunda hari ini?',
        sentAt: DateTime.now(),
        isAi: true,
      ),
    ];
  }
}

final aiChatRepositoryProvider = Provider<AiChatRepository>((ref) {
  return AiChatRepository(ref.watch(apiClientProvider));
});

final aiChatMessagesProvider =
    StateNotifierProvider<AiChatNotifier, List<ChatMessage>>((ref) {
  final repo = ref.watch(aiChatRepositoryProvider);
  return AiChatNotifier(repo);
});
