import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../models/midwife_model.dart';
import '../models/slot_model.dart';

class MidwifeRepository {
  final ApiClient _apiClient;

  MidwifeRepository(this._apiClient);

  Future<List<Midwife>> getMidwives() async {
    final response = await _apiClient.get(ApiEndpoints.midwives);
    final data = _responseData(response.data);

    return data
        .map((item) => Midwife.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<Midwife?> getMidwifeById(String uid) async {
    final midwives = await getMidwives();
    for (final midwife in midwives) {
      if (midwife.uid == uid) return midwife;
    }
    return null;
  }

  Future<List<ConsultationSlot>> getAvailableSlots(String midwifeId) async {
    final response = await _apiClient.get(ApiEndpoints.midwifeSlots(midwifeId));
    final data = _responseData(response.data);

    return data
        .map((item) => ConsultationSlot.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  // ==========================================
  // Midwife Self-Management (Tarif & Jadwal)
  // ==========================================

  Future<Midwife> getMyProfile() async {
    final response = await _apiClient.get(ApiEndpoints.midwifeProfile);
    final map = response.data is Map && response.data['data'] is Map
        ? Map<String, dynamic>.from(response.data['data'] as Map)
        : <String, dynamic>{};
    return Midwife.fromJson(map);
  }

  Future<Midwife> updateMyProfile({
    int? consultationFee,
    String? bio,
    String? displayName,
  }) async {
    final payload = <String, dynamic>{};
    if (consultationFee != null) payload['consultation_fee'] = consultationFee;
    if (bio != null) payload['bio'] = bio;
    if (displayName != null) payload['display_name'] = displayName;

    final response = await _apiClient.patch(
      ApiEndpoints.midwifeProfile,
      data: payload,
    );
    final map = response.data is Map && response.data['data'] is Map
        ? Map<String, dynamic>.from(response.data['data'] as Map)
        : <String, dynamic>{};
    return Midwife.fromJson(map);
  }

  Future<List<ConsultationSlot>> getMySlots() async {
    final response = await _apiClient.get(ApiEndpoints.midwifeOwnSlots);
    final data = _responseData(response.data);

    return data
        .map((item) => ConsultationSlot.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<ConsultationSlot> createSlot(DateTime startAt) async {
    final response = await _apiClient.post(
      ApiEndpoints.midwifeOwnSlots,
      data: {
        'start_at': startAt.toUtc().toIso8601String(),
      },
    );
    final map = response.data is Map && response.data['data'] is Map
        ? Map<String, dynamic>.from(response.data['data'] as Map)
        : <String, dynamic>{};
    return ConsultationSlot.fromJson(map);
  }

  Future<void> deleteSlot(String slotId) async {
    await _apiClient.delete(ApiEndpoints.midwifeOwnSlot(slotId));
  }

  List<dynamic> _responseData(dynamic response) {
    if (response is! Map || response['data'] is! List) {
      throw const FormatException('The API returned an invalid catalog response.');
    }

    return response['data'] as List;
  }
}

final midwifeRepositoryProvider = Provider<MidwifeRepository>(
  (ref) => MidwifeRepository(ref.watch(apiClientProvider)),
);

final midwivesListProvider = FutureProvider<List<Midwife>>((ref) {
  final repo = ref.watch(midwifeRepositoryProvider);
  return repo.getMidwives();
});

final midwifeByIdProvider = FutureProvider.family<Midwife?, String>((ref, uid) {
  final repo = ref.watch(midwifeRepositoryProvider);
  return repo.getMidwifeById(uid);
});

final availableSlotsProvider = FutureProvider.family<List<ConsultationSlot>, String>(
  (ref, midwifeId) {
    final repo = ref.watch(midwifeRepositoryProvider);
    return repo.getAvailableSlots(midwifeId);
  },
);
