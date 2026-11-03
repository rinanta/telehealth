import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/consultation_timer_banner.dart';
import '../../../data/models/booking_model.dart';
import '../../../data/models/chat_message_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/booking_repository.dart';
import '../../../data/repositories/consultation_chat_repository.dart';

class ConsultationChatScreen extends ConsumerStatefulWidget {
  final String bookingId;

  const ConsultationChatScreen({super.key, required this.bookingId});

  @override
  ConsumerState<ConsultationChatScreen> createState() => _ConsultationChatScreenState();
}

class _ConsultationChatScreenState extends ConsumerState<ConsultationChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isTimerExpired = false;

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleSendMessage(Booking booking, bool isMidwife) async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isTimerExpired || booking.isCompleted) return;

    _messageController.clear();
    final user = ref.read(authStateProvider);

    await ref.read(consultationChatProvider.notifier).sendMessage(
          bookingId: widget.bookingId,
          senderId: user?.uid ?? (isMidwife ? 'midwife_001' : 'patient_001'),
          senderName: user?.name ?? (isMidwife ? booking.midwifeName : booking.patientName),
          text: text,
          isMidwife: isMidwife,
        );

    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider);
    final isMidwife = user?.isMidwife ?? false;

    final bookings = ref.watch(bookingsListProvider);
    final booking = bookings.cast<Booking?>().firstWhere(
          (b) => b?.id == widget.bookingId,
          orElse: () => null,
        );

    if (booking == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ruang Konsultasi')),
        body: const Center(child: Text('Data sesi konsultasi tidak ditemukan.')),
      );
    }

    final chatMap = ref.watch(consultationChatProvider);
    final messages = chatMap[widget.bookingId] ?? ref.watch(consultationChatRepositoryProvider).getMessages(widget.bookingId);

    final startedAt = booking.consultationStartedAt ?? DateTime.now();
    final isReadOnly = booking.isCompleted || _isTimerExpired;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isMidwife ? booking.patientName : booking.midwifeName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            Text(
              isMidwife ? 'Konsultasi Pasien • 30 Menit' : 'Bidan Praktik Mandiri Berizin',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          // Jika Bidan: tombol selesai dan isi rekap form (UI-14)
          if (isMidwife && !booking.isCompleted)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check_circle_outline, size: 16),
                label: const Text('Isi Hasil', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                onPressed: () => context.push('/midwife-result-form/${booking.id}'),
              ),
            ),

          if (booking.isCompleted)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.description_outlined, size: 16),
                label: const Text('Lihat Hasil', style: TextStyle(fontSize: 12)),
                onPressed: () => context.push('/consultation-result/${booking.id}'),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Banner Timer Countdown 30 Menit (FR-11)
          if (!booking.isCompleted)
            ConsultationTimerBanner(
              startedAt: startedAt,
              durationMinutes: 30,
              onTimerExpired: () {
                setState(() => _isTimerExpired = true);
              },
            ),

          // Jika Selesai: Banner Read-Only
          if (booking.isCompleted)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: const Color(0xFFF1F5F9),
              child: const Row(
                children: [
                  Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.textSecondary),
                  SizedBox(width: 8),
                  Text(
                    'Sesi telah selesai. Riwayat chat ini bersifat hanya-baca (read-only).',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),

          // Keluhan Awal Pasien
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.assignment_outlined, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Keluhan Awal Pasien:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                      const SizedBox(height: 2),
                      Text(booking.complaint, style: const TextStyle(fontSize: 12, color: AppColors.textPrimary)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Area Chat List
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final msg = messages[index];
                final isMyMessage = isMidwife ? msg.isMidwife : !msg.isMidwife;
                return _buildMessageBubble(msg, isMyMessage);
              },
            ),
          ),

          // Input Bar Pesan (FR-11: Terkunci otomatis jika 30 menit berakhir atau selesai)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: SafeArea(
              child: isReadOnly
                  ? Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _isTimerExpired
                            ? 'Waktu 30 menit telah berakhir. Input pesan dikunci oleh server.'
                            : 'Konsultasi telah ditutup oleh Bidan.',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                      ),
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _messageController,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _handleSendMessage(booking, isMidwife),
                            decoration: InputDecoration(
                              hintText: isMidwife ? 'Ketik tanggapan / saran bidan...' : 'Tulis pesan atau keluhan Bunda...',
                              filled: true,
                              fillColor: AppColors.surfaceVariant,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: isMidwife ? AppColors.secondary : AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                            onPressed: () => _handleSendMessage(booking, isMidwife),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg, bool isMe) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMe
              ? (msg.isMidwife ? AppColors.secondary : AppColors.primary)
              : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          border: isMe ? null : Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 4,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              msg.senderName,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isMe ? Colors.white70 : (msg.isMidwife ? AppColors.secondaryDark : AppColors.primary),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              msg.text,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: isMe ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
