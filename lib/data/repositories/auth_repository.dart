import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';

class AuthRepository {
  AppUser? _currentUser;

  AppUser? get currentUser => _currentUser;

  // Akun Demo Bawaan
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
    bio: 'Bidan Praktik Mandiri berpengalaman 8 tahun spesialisasi ANC dan persalinan nyaman.',
    createdAt: DateTime.now().subtract(const Duration(days: 90)),
  );

  static final AppUser demoMidwifePending = AppUser(
    uid: 'midwife_002',
    name: 'Bdn. Novi Triana, Amd.Keb',
    email: 'bidan.novi@telebunda.id',
    role: 'midwife',
    verified: false, // Menunggu persetujuan admin sesuai FR-02
    credentialLabel: 'Bdn. Novi Triana, Amd.Keb',
    bio: 'Menunggu proses verifikasi dokumen STR oleh tim admin.',
    createdAt: DateTime.now().subtract(const Duration(days: 2)),
  );

  Future<AppUser> login(String email, String password) async {
    await Future.delayed(const Duration(milliseconds: 600));

    if (email == demoPatient.email || email.contains('pasien') || email.contains('anisa')) {
      _currentUser = demoPatient;
      return demoPatient;
    }

    if (email == demoMidwifeVerified.email || email.contains('siti')) {
      _currentUser = demoMidwifeVerified;
      return demoMidwifeVerified;
    }

    if (email == demoMidwifePending.email || email.contains('novi')) {
      _currentUser = demoMidwifePending;
      return demoMidwifePending;
    }

    // Default ke pasien jika input email kustom
    final user = AppUser(
      uid: 'user_${DateTime.now().millisecondsSinceEpoch}',
      name: email.split('@').first,
      email: email,
      role: 'patient',
      verified: true,
      createdAt: DateTime.now(),
    );
    _currentUser = user;
    return user;
  }

  Future<AppUser> registerPatient({
    required String name,
    required String email,
    required String password,
  }) async {
    await Future.delayed(const Duration(milliseconds: 700));
    final user = AppUser(
      uid: 'patient_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      email: email,
      role: 'patient',
      verified: true,
      createdAt: DateTime.now(),
    );
    _currentUser = user;
    return user;
  }

  Future<AppUser> registerMidwife({
    required String name,
    required String email,
    required String password,
    required String credentialLabel,
    required String strNumber,
  }) async {
    await Future.delayed(const Duration(milliseconds: 700));
    // Sesuai PRD Bab 3: registrasi bidan menghasilkan status pending_verification
    final user = AppUser(
      uid: 'midwife_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      email: email,
      role: 'midwife',
      verified: false,
      credentialLabel: credentialLabel,
      bio: 'STR: $strNumber (Menunggu Verifikasi Admin)',
      createdAt: DateTime.now(),
    );
    _currentUser = user;
    return user;
  }

  void setCurrentUser(AppUser? user) {
    _currentUser = user;
  }

  Future<void> logout() async {
    await Future.delayed(const Duration(milliseconds: 200));
    _currentUser = null;
  }
}

// StateNotifier untuk Current User
class AuthNotifier extends StateNotifier<AppUser?> {
  final AuthRepository _repo;

  AuthNotifier(this._repo) : super(null);

  Future<AppUser> login(String email, String password) async {
    final user = await _repo.login(email, password);
    state = user;
    return user;
  }

  Future<AppUser> registerPatient(String name, String email, String password) async {
    final user = await _repo.registerPatient(name: name, email: email, password: password);
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

  void switchDemoUser(AppUser user) {
    _repo.setCurrentUser(user);
    state = user;
  }

  Future<void> logout() async {
    await _repo.logout();
    state = null;
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository());

final authStateProvider = StateNotifierProvider<AuthNotifier, AppUser?>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  return AuthNotifier(repo);
});
