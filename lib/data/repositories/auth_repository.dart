import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../models/user_model.dart';

class AuthRepository {
  final FirebaseAuth? _firebaseAuth;
  final ApiClient _apiClient;
  AppUser? _currentUser;
  FirebaseAuth get _auth => _firebaseAuth ?? FirebaseAuth.instance;

  AuthRepository({FirebaseAuth? firebaseAuth, required ApiClient apiClient})
    : _firebaseAuth = firebaseAuth,
      _apiClient = apiClient {
    _apiClient.setTokenProvider(() async {
      return _auth.currentUser?.getIdToken();
    });
  }

  AppUser? get currentUser => _currentUser;

  Future<AppUser> login(String email, String password) async {
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

  Future<AppUser?> restoreSession() async {
    if (Firebase.apps.isEmpty || _auth.currentUser == null) return null;
    _currentUser = await _fetchProfile();
    return _currentUser;
  }

  Future<void> logout() async {
    if (Firebase.apps.isNotEmpty) {
      await _auth.signOut();
    }
    _apiClient.setAuthToken(null);
    _currentUser = null;
  }

  Future<void> _createFirebaseAccount(String email, String password) async {
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
