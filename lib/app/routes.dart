import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/repositories/auth_repository.dart';
import '../features/ai_chat/screens/ai_chat_screen.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/midwife_pending_screen.dart';
import '../features/auth/screens/register_screen.dart';
import '../features/auth/screens/splash_screen.dart';
import '../features/booking/screens/booking_form_screen.dart';
import '../features/booking/screens/booking_status_screen.dart';
import '../features/booking/screens/mayar_checkout_screen.dart';
import '../data/models/booking_hold_model.dart';
import '../features/consultation/screens/consultation_chat_screen.dart';
import '../features/consultation_result/screens/consultation_result_screen.dart';
import '../features/consultation_result/screens/midwife_result_form_screen.dart';
import '../features/consultation_result/screens/patient_history_screen.dart';
import '../features/midwife_catalog/screens/midwife_catalog_screen.dart';
import '../features/midwife_catalog/screens/midwife_detail_screen.dart';
import '../features/midwife_dashboard/screens/midwife_booking_detail_screen.dart';
import '../features/midwife_dashboard/screens/midwife_dashboard_screen.dart';
import '../features/midwife_dashboard/screens/midwife_history_screen.dart';
import '../features/patient_dashboard/screens/patient_dashboard_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final user = ref.read(authStateProvider);
      final path = state.uri.path;
      final isPublicRoute =
          path == '/' || path == '/login' || path == '/register';

      // 1. Jika belum login dan mencoba masuk ke rute privat
      if (user == null && !isPublicRoute) {
        return '/login';
      }

      // 2. Proteksi Role Bidan (FR-02 & FR-03)
      final isMidwifeRoute =
          path.startsWith('/midwife-dashboard') ||
          path.startsWith('/midwife-booking-detail') ||
          path.startsWith('/midwife-result-form') ||
          path.startsWith('/midwife-history');

      if (user != null) {
        // Jika Pasien mencoba membuka rute Bidan
        if (isMidwifeRoute && user.isPatient) {
          return '/patient-dashboard';
        }

        // Jika Bidan belum diverifikasi mencoba membuka rute Bidan
        if (isMidwifeRoute && user.isMidwife && !user.verified) {
          return '/midwife-pending';
        }

        // Jika sudah login dan membuka Splash/Login/Register
        if (isPublicRoute && path != '/') {
          return user.isPatient
              ? '/patient-dashboard'
              : (user.verified ? '/midwife-dashboard' : '/midwife-pending');
        }
      }

      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/midwife-pending',
        builder: (context, state) => const MidwifePendingScreen(),
      ),
      GoRoute(
        path: '/patient-dashboard',
        builder: (context, state) => const PatientDashboardScreen(),
      ),
      GoRoute(
        path: '/ai-chat',
        builder: (context, state) => const AiChatScreen(),
      ),
      GoRoute(
        path: '/midwife-catalog',
        builder: (context, state) => const MidwifeCatalogScreen(),
      ),
      GoRoute(
        path: '/midwife-detail/:id',
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return MidwifeDetailScreen(midwifeId: id);
        },
      ),
      GoRoute(
        path: '/booking-form/:midwifeId',
        builder: (context, state) {
          final midwifeId = state.pathParameters['midwifeId'] ?? '';
          return BookingFormScreen(midwifeId: midwifeId);
        },
      ),
      GoRoute(
        path: '/mayar-checkout/:bookingId',
        builder: (context, state) {
          final bookingId = state.pathParameters['bookingId'] ?? '';
          return MayarCheckoutScreen(bookingId: bookingId);
        },
      ),
      GoRoute(
        path: '/booking-status/:bookingId',
        builder: (context, state) {
          final bookingId = state.pathParameters['bookingId'] ?? '';
          final bookingHold = state.extra;
          return BookingStatusScreen(
            bookingId: bookingId,
            bookingHold: bookingHold is BookingHold ? bookingHold : null,
          );
        },
      ),
      GoRoute(
        path: '/consultation-chat/:bookingId',
        builder: (context, state) {
          final bookingId = state.pathParameters['bookingId'] ?? '';
          return ConsultationChatScreen(bookingId: bookingId);
        },
      ),
      GoRoute(
        path: '/consultation-result/:bookingId',
        builder: (context, state) {
          final bookingId = state.pathParameters['bookingId'] ?? '';
          return ConsultationResultScreen(bookingId: bookingId);
        },
      ),
      GoRoute(
        path: '/patient-history',
        builder: (context, state) => const PatientHistoryScreen(),
      ),
      GoRoute(
        path: '/midwife-dashboard',
        builder: (context, state) => const MidwifeDashboardScreen(),
      ),
      GoRoute(
        path: '/midwife-booking-detail/:bookingId',
        builder: (context, state) {
          final bookingId = state.pathParameters['bookingId'] ?? '';
          return MidwifeBookingDetailScreen(bookingId: bookingId);
        },
      ),
      GoRoute(
        path: '/midwife-result-form/:bookingId',
        builder: (context, state) {
          final bookingId = state.pathParameters['bookingId'] ?? '';
          return MidwifeResultFormScreen(bookingId: bookingId);
        },
      ),
      GoRoute(
        path: '/midwife-history',
        builder: (context, state) => const MidwifeHistoryScreen(),
      ),
    ],
  );

  ref.listen(authStateProvider, (previous, next) {
    router.refresh();
  });
  ref.onDispose(router.dispose);

  return router;
});
