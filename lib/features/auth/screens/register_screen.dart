import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_button.dart';
import '../../../data/repositories/auth_repository.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  int _selectedTab = 0; // 0 = Pasien, 1 = Bidan

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // Field khusus bidan
  final _credentialController = TextEditingController();
  final _strController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _credentialController.dispose();
    _strController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (_nameController.text.trim().isEmpty ||
        _emailController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Harap lengkapi seluruh kolom formulir.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (_selectedTab == 0) {
        // Daftar Pasien
        await ref.read(authStateProvider.notifier).registerPatient(
              _nameController.text.trim(),
              _emailController.text.trim(),
              _passwordController.text,
            );
        if (!mounted) return;
        context.go('/patient-dashboard');
      } else {
        // Pengajuan Akun Bidan
        if (_credentialController.text.trim().isEmpty || _strController.text.trim().isEmpty) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Gelar kebidanan dan nomor STR wajib diisi untuk verifikasi.';
          });
          return;
        }

        await ref.read(authStateProvider.notifier).registerMidwife(
              name: _nameController.text.trim(),
              email: _emailController.text.trim(),
              password: _passwordController.text,
              credentialLabel: _credentialController.text.trim(),
              strNumber: _strController.text.trim(),
            );

        if (!mounted) return;
        context.go('/midwife-pending');
      }
    } catch (e) {
      setState(() => _errorMessage = 'Pendaftaran gagal. Silakan coba lagi.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Daftar Akun'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Segmented Role Switcher (Pasien vs Bidan)
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => _selectedTab = 0),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _selectedTab == 0 ? Colors.white : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: _selectedTab == 0
                                ? [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.05),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    )
                                  ]
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Pasien / Ibu Hamil',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _selectedTab == 0 ? AppColors.primary : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => _selectedTab = 1),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _selectedTab == 1 ? Colors.white : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: _selectedTab == 1
                                ? [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.05),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    )
                                  ]
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Mitra Bidan',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _selectedTab == 1 ? AppColors.secondary : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              if (_selectedTab == 1)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: AppColors.infoContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, size: 20, color: AppColors.info),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Pendaftaran Bidan memerlukan verifikasi keaslian STR oleh tim administrasi medis sebelum dapat membuka praktik.',
                          style: TextStyle(fontSize: 12, color: Color(0xFF1E3A8A)),
                        ),
                      ),
                    ],
                  ),
                ),

              // Form Nama Lengkap
              Text(
                _selectedTab == 0 ? 'Nama Lengkap Ibu' : 'Nama Lengkap & Gelar Bidan',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  hintText: _selectedTab == 0 ? 'Contoh: Bunda Anisa Lestari' : 'Contoh: Bdn. Siti Rahmawati, S.Tr.Keb',
                  prefixIcon: const Icon(Icons.person_outline_rounded, color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(height: 16),

              // Form Email
              const Text('Email Aktif', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  hintText: 'nama@email.com',
                  prefixIcon: Icon(Icons.email_outlined, color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(height: 16),

              // Kolom Tambahan Jika Bidan
              if (_selectedTab == 1) ...[
                const Text('Gelar & Kredensial', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 8),
                TextField(
                  controller: _credentialController,
                  decoration: const InputDecoration(
                    hintText: 'Contoh: Bidan Praktik Mandiri • Spesialis ANC',
                    prefixIcon: Icon(Icons.badge_outlined, color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(height: 16),

                const Text('Nomor Registrasi Bidan (STR Aktif)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 8),
                TextField(
                  controller: _strController,
                  decoration: const InputDecoration(
                    hintText: 'STR-BDN-XXXX-XXXX',
                    prefixIcon: Icon(Icons.verified_outlined, color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Kata Sandi
              const Text('Kata Sandi', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  hintText: 'Minimal 8 karakter',
                  prefixIcon: Icon(Icons.lock_outline_rounded, color: AppColors.textSecondary),
                ),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(_errorMessage!, style: const TextStyle(fontSize: 12, color: AppColors.danger)),
              ],

              const SizedBox(height: 24),
              AppButton(
                label: _selectedTab == 0 ? 'Daftar sebagai Pasien' : 'Kirim Pengajuan Kemitraan Bidan',
                isLoading: _isLoading,
                backgroundColor: _selectedTab == 0 ? AppColors.primary : AppColors.secondary,
                onPressed: _handleRegister,
              ),

              const SizedBox(height: 20),
              Center(
                child: TextButton(
                  onPressed: () => context.pop(),
                  child: const Text('Sudah punya akun? Masuk di sini'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
