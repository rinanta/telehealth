import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:telebunda_app/main.dart';

void main() {
  testWidgets('TeleBunda AI Splash Screen Smoke Test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: TeleBundaApp(),
      ),
    );

    await tester.pumpAndSettle();

    // Pastikan teks judul TeleBunda AI tampil
    expect(find.text('TeleBunda AI'), findsWidgets);
    expect(find.text('Masuk ke Akun'), findsOneWidget);
    expect(find.text('Daftar Akun Baru'), findsOneWidget);
  });
}
