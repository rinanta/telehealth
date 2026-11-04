import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../models/user_model.dart';

class AuthRepository {
  final FirebaseAuth? _firebaseAuth;
  final ApiClient _apiClient;
  bool _usingDemoAccount = false;
  AppUser? _currentUser;
  FirebaseAuth get _auth => _firebaseAuth ?? FirebaseAuth.instance;

  AuthRepository({FirebaseAuth? firebaseAuth, required ApiClient apiClient})
    : _firebaseAuth = firebaseAuth,
      _apiClient = apiClient {
    _apiClient.setTokenProvider(() async {
      if (_usingDemoAccount) return null;
      return _auth.currentUser?.getIdToken();
    });
  }

  AppUser? get currentUser => _currentUser;

  static final AppUser demoPatient = AppUser(
    uid: 'patient_001',
    name: 'Bunda Anisa Lestari',
    email: 'pasien@telebunda.id',
    role: 'patient',
    verified: true,
    bio: 'Ibu hamil trimester kedua (usia kehamilan 22 minggu)',
    createdAt: DateTime.now().subtract(const Duration(days: 30)),
  );

  static final AppUser demoMidwifeVerified = AppUser(
    uid: 'midwife_001',
    name: 'Bdn. Siti Rahmawati, S.Tr.Keb',
    email: 'bidan.siti@telebunda.id',
    role: 'midwife',
    verified: true,
    credentialLabel: 'Bdn. Siti Rahmawati, S.Tr.Keb',
    bio:
        'Bidan Praktik Mandiri berpengalaman 8 tahun spesialisasi ANC dan persalinan nyaman.',
    createdAt: DateTime.now().subtract(const Duration(days: 90)),
  );

  static final AppUser demoMidwifePending = AppUser(
    uid: 'midwife_002',
    name: 'Bdn. Novi Triana, Amd.Keb',
    email: 'bidan.novi@telebunda.id',
    role: 'midwife',
    verified: false,
    credentialLabel: 'Bdn. Novi Triana, Amd.Keb',
    bio: 'Menunggu proses verifikasi dokumen STR oleh tim admin.',
    createdAt: DateTime.now().subtract(const Duration(days: 2)),
  );

  Future<AppUser> login(String email, String password) async {
    if (kDebugMode && email == demoPatient.email) {
      return _useDemoUser(demoPatient);
    }
    if (kDebugMode && email == demoMidwifeVerified.email) {
      return _useDemoUser(demoMidwifeVerified);
    }
    if (kDebugMode && email == demoMidwifePending.email) {
      return _useDemoUser(demoMidwifePending);
    }

    _usingDemoAccount = false;
    _apiClient.setAuthToken(null);
    await _auth.signInWithEmailAndPassword(email: email, password: password);
    _currentUser = await _fetchProfile();
    return _currentUser!;
  }

  Future<AppUser> registerPatient({
    required String name,
    required String email,
    required String password,
  }) async {
    await _createFirebaseAccount(email, password);
    _currentUser = await _registerProfile({'name': name, 'role': 'patient'});
    return _currentUser!;
  }

  Future<AppUser> registerMidwife({
    required String name,
    required String email,
    required String password,
    required String credentialLabel,
    required String strNumber,
  }) async {
    await _createFirebaseAccount(email, password);
    _currentUser = await _registerProfile({
      'name': name,
      'role': 'midwife',
      'credential_label': credentialLabel,
      'str_number': strNumber,
    });
    return _currentUser!;
  }

  void setCurrentUser(AppUser? user) {
    _currentUser = user;
    _usingDemoAccount = user != null;
    _apiClient.setAuthToken(null);
  }

  Future<AppUser?> restoreSession() async {
    if (Firebase.apps.isEmpty || _auth.currentUser == null) return null;
    _usingDemoAccount = false;
    _currentUser = await _fetchProfile();
    return _currentUser;
  }

  Future<void> logout() async {
    if (Firebase.apps.isNotEmpty) {
      await _auth.signOut();
    }
    _usingDemoAccount = false;
    _apiClient.setAuthToken(null);
    _currentUser = null;
  }

  Future<void> _createFirebaseAccount(String email, String password) async {
    _usingDemoAccount = false;
    _apiClient.setAuthToken(null);

    try {
      await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (error) {
      if (error.code != 'email-already-in-use') rethrow;
      await _auth.signInWithEmailAndPassword(email: email, password: password);
    }
  }

  Future<AppUser> _registerProfile(Map<String, dynamic> profile) async {
    final response = await _apiClient.post(
      ApiEndpoints.register,
      data: profile,
    );
    return _parseProfile(response.data);
  }

  Future<AppUser> _fetchProfile() async {
    final response = await _apiClient.get(ApiEndpoints.me);
    return _parseProfile(response.data);
  }

  AppUser _parseProfile(dynamic response) {
    if (response is! Map || response['data'] is! Map) {
      throw const FormatException('The API returned an invalid user profile.');
    }
    return AppUser.fromJson(Map<String, dynamic>.from(response['data'] as Map));
  }

  AppUser _useDemoUser(AppUser user) {
    _usingDemoAccount = true;
    _apiClient.setAuthToken(null);
    _currentUser = user;
    return user;
  }
}

class AuthNotifier extends StateNotifier<AppUser?> {
  final AuthRepository _repo;

  AuthNotifier(this._repo) : super(null);

  Future<AppUser> login(String email, String password) async {
    final user = await _repo.login(email, password);
    state = user;
    return user;
  }

  Future<AppUser> registerPatient(
    String name,
    String email,
    String password,
  ) async {
    final user = await _repo.registerPatient(
      name: name,
      email: email,
      password: password,
    );
    state = user;
    return user;
  }

  Future<AppUser> registerMidwife({
    required String name,
    required String email,
    required String password,
    required String credentialLabel,
    required String strNumber,
  }) async {
    final user = await _repo.registerMidwife(
      name: name,
      email: email,
      password: password,
      credentialLabel: credentialLabel,
      strNumber: strNumber,
    );
    state = user;
    return user;
  }

  Future<String?> restoreSession() async {
    try {
      state = await _repo.restoreSession();
      return null;
    } on FirebaseAuthException catch (error) {
      return describeAuthError(error);
    } on DioException catch (error) {
      return describeAuthError(error);
    }
  }

  void switchDemoUser(AppUser user) {
    _repo.setCurrentUser(user);
    state = user;
  }

  Future<void> logout() async {
    await _repo.logout();
    state = null;
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(apiClient: ref.watch(apiClientProvider));
});

final authStateProvider = StateNotifierProvider<AuthNotifier, AppUser?>((ref) {
  final notifier = AuthNotifier(ref.watch(authRepositoryProvider));
  unawaited(
    notifier.restoreSession().then((error) {
      if (error != null) {
        ref.read(authRestoreErrorProvider.notifier).state = error;
      }
    }),
  );
  return notifier;
});

final authRestoreErrorProvider = StateProvider<String?>((ref) => null);

String describeAuthError(Object error) {
  if (error is FirebaseAuthException) {
    return switch (error.code) {
      'invalid-email' => 'Format email tidak valid.',
      'user-disabled' => 'Akun ini dinonaktifkan.',
      'user-not-found' ||
      'wrong-password' ||
      'invalid-credential' => 'Email atau kata sandi tidak sesuai.',
      'email-already-in-use' => 'Email sudah terdaftar.',
      'weak-password' => 'Kata sandi terlalu lemah.',
      'network-request-failed' =>
        'Tidak dapat terhubung ke Firebase. Periksa jaringan Anda.',
      _ => 'Autentikasi gagal. Silakan coba lagi.',
    };
  }

  if (error is DioException) {
    final body = error.response?.data;
    if (body is Map && body['message'] is String) {
      return body['message'] as String;
    }
    return 'Tidak dapat menghubungi server. Pastikan backend berjalan dan jaringan tersedia.';
  }

  return 'Terjadi kesalahan saat memproses akun. Silakan coba lagi.';
}
