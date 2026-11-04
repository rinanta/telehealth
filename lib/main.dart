import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/routes.dart';
import 'core/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (defaultTargetPlatform == TargetPlatform.android) {
    await Firebase.initializeApp();
  }
  await initializeDateFormatting('id_ID', null);

  runApp(const ProviderScope(child: TeleBundaApp()));
}

class TeleBundaApp extends ConsumerWidget {
  const TeleBundaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'TeleBunda AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: router,
      builder: (context, child) {
        return Container(
          color: const Color(
            0xFFF1F5F9,
          ), // Background canvas elegan di layar desktop
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 480,
            ), // Ukuran ideal smartphone
            child: ClipRect(child: child),
          ),
        );
      },
    );
  }
}
