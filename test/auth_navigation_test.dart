import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:telebunda_app/app/routes.dart';
import 'package:telebunda_app/data/repositories/auth_repository.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('id_ID', null);
  });

  testWidgets('router keeps its state and redirects after authentication', (
    tester,
  ) async {
    final container = ProviderContainer();
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

    container
        .read(authStateProvider.notifier)
        .switchDemoUser(AuthRepository.demoPatient);
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
