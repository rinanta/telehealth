import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telebunda_app/data/models/midwife_model.dart';
import 'package:telebunda_app/data/repositories/midwife_repository.dart';
import 'package:telebunda_app/features/midwife_catalog/screens/midwife_catalog_screen.dart';

void main() {
  testWidgets('shows an empty state when the API returns no midwives', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          midwivesListProvider.overrideWith((ref) async => <Midwife>[]),
        ],
        child: const MaterialApp(home: MidwifeCatalogScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Belum ada bidan terverifikasi yang tersedia.'),
      findsOneWidget,
    );
  });

  testWidgets('shows a retry action when the catalog API fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          midwivesListProvider.overrideWith((ref) async {
            throw Exception('network unavailable');
          }),
        ],
        child: const MaterialApp(home: MidwifeCatalogScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Katalog bidan tidak dapat dimuat. Periksa koneksi lalu coba lagi.',
      ),
      findsOneWidget,
    );
    expect(find.text('Coba lagi'), findsOneWidget);
  });
}
