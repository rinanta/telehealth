import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../data/models/midwife_model.dart';
import '../../../data/models/slot_model.dart';
import '../../../data/repositories/midwife_repository.dart';

final myMidwifeProfileProvider = FutureProvider<Midwife>((ref) {
  return ref.watch(midwifeRepositoryProvider).getMyProfile();
});

final myMidwifeSlotsProvider = FutureProvider<List<ConsultationSlot>>((ref) {
  return ref.watch(midwifeRepositoryProvider).getMySlots();
});

class MidwifeManagementScreen extends ConsumerStatefulWidget {
  const MidwifeManagementScreen({super.key});

  @override
  ConsumerState<MidwifeManagementScreen> createState() => _MidwifeManagementScreenState();
}

class _MidwifeManagementScreenState extends ConsumerState<MidwifeManagementScreen> {
  final _feeController = TextEditingController();
  bool _savingFee = false;
  bool _addingSlot = false;

  @override
  void dispose() {
    _feeController.dispose();
    super.dispose();
  }

  Future<void> _saveFee() async {
    final fee = int.tryParse(_feeController.text.replaceAll('.', '').replaceAll(',', ''));
    if (fee == null || fee < 1000) {
      _showMessage('Tarif minimal Rp1.000.');
      return;
    }

    setState(() => _savingFee = true);
    try {
      await ref.read(midwifeRepositoryProvider).updateMyProfile(consultationFee: fee);
      ref.invalidate(myMidwifeProfileProvider);
      ref.invalidate(midwivesListProvider);
      if (mounted) _showMessage('Tarif konsultasi berhasil disimpan.');
    } catch (_) {
      if (mounted) _showMessage('Tarif gagal disimpan. Coba lagi.');
    } finally {
      if (mounted) setState(() => _savingFee = false);
    }
  }

  Future<void> _addSlot() async {
    final today = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      initialDate: today.add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (time == null) return;

    final start = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (!start.isAfter(DateTime.now())) {
      _showMessage('Jadwal harus berada di masa depan.');
      return;
    }

    setState(() => _addingSlot = true);
    try {
      await ref.read(midwifeRepositoryProvider).createSlot(start);
      ref.invalidate(myMidwifeSlotsProvider);
      ref.invalidate(availableSlotsProvider);
      if (mounted) _showMessage('Jadwal berhasil ditambahkan.');
    } catch (_) {
      if (mounted) _showMessage('Jadwal bentrok atau gagal disimpan.');
    } finally {
      if (mounted) setState(() => _addingSlot = false);
    }
  }

  Future<void> _deleteSlot(ConsultationSlot slot) async {
    if (!slot.isAvailable) {
      _showMessage('Jadwal yang sudah dipesan tidak dapat dihapus.');
      return;
    }

    try {
      await ref.read(midwifeRepositoryProvider).deleteSlot(slot.id);
      ref.invalidate(myMidwifeSlotsProvider);
      ref.invalidate(availableSlotsProvider);
      if (mounted) _showMessage('Jadwal dihapus.');
    } catch (_) {
      if (mounted) _showMessage('Jadwal gagal dihapus.');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(myMidwifeProfileProvider);
    final slots = ref.watch(myMidwifeSlotsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan Praktik')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myMidwifeProfileProvider);
          ref.invalidate(myMidwifeSlotsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('Tarif konsultasi', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            profile.when(
              loading: () => const LinearProgressIndicator(),
              error: (err, stack) => const Text('Profil gagal dimuat.'),
              data: (data) {
                if (_feeController.text.isEmpty && data.price != null) {
                  _feeController.text = data.price.toString();
                }
                return Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _feeController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          prefixText: 'Rp ',
                          border: OutlineInputBorder(),
                          hintText: 'Contoh: 75000',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _savingFee ? null : _saveFee,
                      child: _savingFee ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator()) : const Text('Simpan'),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Jadwal praktik', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                FilledButton.icon(
                  onPressed: _addingSlot ? null : _addSlot,
                  icon: const Icon(Icons.add),
                  label: const Text('Tambah'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Setiap jadwal berlangsung 30 menit. Jadwal yang sudah dipesan tidak dapat diubah atau dihapus.'),
            const SizedBox(height: 12),
            slots.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => const Text('Jadwal gagal dimuat.'),
              data: (items) => items.isEmpty
                  ? const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('Belum ada jadwal.')))
                  : Column(children: items.map(_slotTile).toList()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slotTile(ConsultationSlot slot) {
    final start = Formatters.formatDateTime(slot.startAt);
    final end = Formatters.formatTime(slot.endAt);
    final status = slot.status == 'available' ? 'Tersedia' : 'Sudah dipesan';

    return Card(
      child: ListTile(
        leading: Icon(slot.isAvailable ? Icons.event_available : Icons.event_busy),
        title: Text('$start - $end'),
        subtitle: Text(status),
        trailing: slot.isAvailable
            ? IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _deleteSlot(slot))
            : const Icon(Icons.lock_outline),
      ),
    );
  }
}
