import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/midwife_model.dart';
import '../models/slot_model.dart';

class MidwifeRepository {
  final List<Midwife> _midwives = [
    const Midwife(
      uid: 'midwife_001',
      name: 'Bdn. Siti Rahmawati, S.Tr.Keb',
      credentialLabel: 'Bidan Praktik Mandiri • Spesialis ANC',
      bio: 'Lulusan Kebidanan Universitas Indonesia dengan pengalaman 8 tahun mendampingi 500+ ibu hamil dan pasca salin. Fokus pada kehamilan sehat, hypnobirthing, dan nutrisi maternal.',
      rating: 4.95,
      reviewCount: 142,
      experienceYears: 8,
      price: 50000,
      strNumber: 'STR-BDN-2021-88912',
      hospitalAffiliation: 'Klinik Pratama Bunda Sehat Jakarta',
    ),
    const Midwife(
      uid: 'midwife_003',
      name: 'Bdn. Nurul Hidayah, M.Keb',
      credentialLabel: 'Magister Kebidanan • Konselor Laktasi',
      bio: 'Praktisi kebidanan klinis dan konselor laktasi bersertifikasi. Berpengalaman menangani keluhan mual muntah berlebih (hiperemesis), persiapan persalinan normal, serta inisiasi menyusu dini.',
      rating: 4.9,
      reviewCount: 98,
      experienceYears: 10,
      price: 65000,
      strNumber: 'STR-BDN-2019-44120',
      hospitalAffiliation: 'RS Ibu & Anak Permata Bunda',
    ),
    const Midwife(
      uid: 'midwife_004',
      name: 'Bdn. Dewi Lestari, Amd.Keb',
      credentialLabel: 'Bidan Komunitas • Senam Hamil',
      bio: 'Bidan ramah dan komunikatif dengan fokus pada kesehatan fisik ibu hamil, senam hamil, dan relaksasi pernapasan menjelang HPL.',
      rating: 4.88,
      reviewCount: 76,
      experienceYears: 6,
      price: 45000,
      strNumber: 'STR-BDN-2022-11309',
      hospitalAffiliation: 'Puskesmas Tebet & PMB Dewi',
    ),
  ];

  List<Midwife> getMidwives() => _midwives;

  Midwife? getMidwifeById(String uid) {
    try {
      return _midwives.firstWhere((m) => m.uid == uid);
    } catch (_) {
      return null;
    }
  }

  List<ConsultationSlot> getAvailableSlots(String midwifeId) {
    final now = DateTime.now();
    // Buat slot hari ini dan besok
    return [
      ConsultationSlot(
        id: 'slot_${midwifeId}_1',
        midwifeId: midwifeId,
        startAt: DateTime(now.year, now.month, now.day, now.hour + 1, 0),
        endAt: DateTime(now.year, now.month, now.day, now.hour + 1, 30),
      ),
      ConsultationSlot(
        id: 'slot_${midwifeId}_2',
        midwifeId: midwifeId,
        startAt: DateTime(now.year, now.month, now.day, now.hour + 2, 0),
        endAt: DateTime(now.year, now.month, now.day, now.hour + 2, 30),
      ),
      ConsultationSlot(
        id: 'slot_${midwifeId}_3',
        midwifeId: midwifeId,
        startAt: DateTime(now.year, now.month, now.day, now.hour + 3, 30),
        endAt: DateTime(now.year, now.month, now.day, now.hour + 4, 0),
      ),
      ConsultationSlot(
        id: 'slot_${midwifeId}_4',
        midwifeId: midwifeId,
        startAt: DateTime(now.year, now.month, now.day + 1, 9, 0),
        endAt: DateTime(now.year, now.month, now.day + 1, 9, 30),
      ),
      ConsultationSlot(
        id: 'slot_${midwifeId}_5',
        midwifeId: midwifeId,
        startAt: DateTime(now.year, now.month, now.day + 1, 14, 0),
        endAt: DateTime(now.year, now.month, now.day + 1, 14, 30),
      ),
    ];
  }
}

final midwifeRepositoryProvider = Provider<MidwifeRepository>((ref) => MidwifeRepository());

final midwivesListProvider = Provider<List<Midwife>>((ref) {
  final repo = ref.watch(midwifeRepositoryProvider);
  return repo.getMidwives();
});
