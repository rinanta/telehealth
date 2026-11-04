import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:telebunda_app/app/routes.dart';
import 'package:telebunda_app/core/network/api_client.dart';
import 'package:telebunda_app/data/repositories/auth_repository.dart';
import 'package:telebunda_app/data/models/user_model.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('id_ID', null);
  });

  testWidgets('router keeps its state and redirects after authentication', (
    tester,
  ) async {
    final notifier = _TestAuthNotifier();
    final container = ProviderContainer(
      overrides: [authStateProvider.overrideWith((ref) => notifier)],
    );
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = container.read(routerProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    router.go('/register');
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.path, '/register');

    notifier.authenticate(
      AppUser(
        uid: 'patient-authenticated',
        name: 'Pasien',
        email: 'patient@example.test',
        role: 'patient',
        verified: true,
        createdAt: DateTime(2026, 1, 1),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      container.read(routerProvider),
      same(router),
      reason:
          'Authentication changes should refresh, not recreate, the router.',
    );
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/patient-dashboard',
    );
  });
}

class _TestAuthNotifier extends AuthNotifier {
  _TestAuthNotifier() : super(AuthRepository(apiClient: ApiClient()));

  void authenticate(AppUser user) {
    state = user;
  }
}
