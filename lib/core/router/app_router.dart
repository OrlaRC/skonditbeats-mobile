import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/presentation/audit_screen.dart';
import '../../features/admin/presentation/beats_admin_screen.dart';
import '../../features/transfers/presentation/transfers_screen.dart';
import '../../features/admin/presentation/dashboard_screen.dart';
import '../../features/admin/presentation/messages_screen.dart';
import '../../features/admin/presentation/users_screen.dart';
import '../../features/auth/presentation/app_lock_controller.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/auth/presentation/screens/lock_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/otp_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/home/presentation/admin_home_screen.dart';
import '../../features/cart/presentation/cart_screen.dart';
import '../../features/catalog/presentation/packs_screen.dart';
import '../../features/catalog/presentation/store_screen.dart';
import '../../features/checkout/presentation/payment_screen.dart';
import '../../features/contact/presentation/contact_screen.dart';
import '../../features/contact/presentation/my_messages_screen.dart';
import '../../features/contact/presentation/thread_screen.dart';
import '../../features/home/presentation/client_home_screen.dart';
import '../../features/home/presentation/client_shell.dart';
import '../../features/legal/terms_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';

class Routes {
  Routes._();

  static const splash = '/splash';
  static const login = '/login';
  static const register = '/register';
  static const otp = '/otp';
  static const terms = '/terminos';
  static const lock = '/bloqueo';
  static const profile = '/perfil';
  static const clientHome = '/app/inicio';
  static const store = '/app/tienda';
  static const packs = '/app/paquetes';
  static const cart = '/app/carrito';
  static const payment = '/app/pago';
  static const contact = '/app/contacto';
  static const adminHome = '/admin/home';
  static const myMessages = '/app/mensajes';
  static String myMessage(String id) => '$myMessages/$id';
  static String adminMessage(String id) => '$adminMessages/$id';
  static const adminUsers = '/admin/usuarios';
  static const adminMessages = '/admin/mensajes';
  static const adminAudit = '/admin/auditoria';
  static const adminDashboard = '/admin/dashboard';
  static const adminBeats = '/admin/beats';
  static const transferencias = '/transferencias';

  static const _public = {login, register, otp, terms};

  static String homeFor(AuthState s) => s.user!.isAdmin ? adminHome : clientHome;
}

final routerProvider = Provider<GoRouter>((ref) {
  // Puente entre Riverpod y go_router: cada cambio de sesión o de bloqueo
  // vuelve a evaluar el redirect.
  final refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  ref.listen(appLockProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final s = ref.read(authControllerProvider);
      final locked = ref.read(appLockProvider);
      final loc = state.matchedLocation;

      if (s.status == AuthStatus.unknown) return loc == Routes.splash ? null : Routes.splash;

      if (s.status == AuthStatus.unauthenticated) {
        return Routes._public.contains(loc) ? null : Routes.login;
      }

      // Logueado pero bloqueado: solo puede ver la pantalla de desbloqueo.
      if (locked) return loc == Routes.lock ? null : Routes.lock;

      // Logueado: no tiene sentido ver login/registro/splash/bloqueo.
      if (loc == Routes.splash ||
          loc == Routes.lock ||
          (Routes._public.contains(loc) && loc != Routes.terms)) {
        return Routes.homeFor(s);
      }

      // A diferencia de la web, aquí también se valida el rol en la navegación.
      if (loc.startsWith('/admin') && !s.user!.isAdmin) return Routes.clientHome;

      return null;
    },
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(path: Routes.register, builder: (_, _) => const RegisterScreen()),
      GoRoute(
        path: Routes.otp,
        redirect: (_, state) => state.extra is OtpArgs ? null : Routes.login,
        builder: (_, state) => OtpScreen(args: state.extra! as OtpArgs),
      ),
      GoRoute(path: Routes.terms, builder: (_, _) => const TermsScreen()),
      GoRoute(path: Routes.lock, builder: (_, _) => const LockScreen()),
      GoRoute(path: Routes.profile, builder: (_, _) => const ProfileScreen()),
      // Cliente: pestañas con barra inferior; cada una conserva su estado.
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => ClientShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.clientHome, builder: (_, _) => const ClientHomeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.store, builder: (_, _) => const StoreScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.packs, builder: (_, _) => const PacksScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.cart, builder: (_, _) => const CartScreen()),
          ]),
        ],
      ),
      // Pantallas completas (sin barra inferior).
      GoRoute(path: Routes.payment, builder: (_, _) => const PaymentScreen()),
      GoRoute(path: Routes.contact, builder: (_, _) => const ContactScreen()),
      GoRoute(path: Routes.adminHome, builder: (_, _) => const AdminHomeScreen()),
      GoRoute(path: Routes.adminUsers, builder: (_, _) => const UsersScreen()),
      GoRoute(
        path: Routes.adminMessages,
        builder: (_, _) => const MessagesScreen(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (_, state) => ThreadScreen(id: state.pathParameters['id']!, admin: true),
          ),
        ],
      ),
      GoRoute(
        path: Routes.myMessages,
        builder: (_, _) => const MyMessagesScreen(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (_, state) => ThreadScreen(id: state.pathParameters['id']!, admin: false),
          ),
        ],
      ),
      GoRoute(path: Routes.adminAudit, builder: (_, _) => const AuditScreen()),
      GoRoute(path: Routes.adminDashboard, builder: (_, _) => const DashboardScreen()),
      GoRoute(path: Routes.adminBeats, builder: (_, _) => const BeatsAdminScreen()),
      GoRoute(path: Routes.transferencias, builder: (_, _) => const TransfersScreen()),
    ],
  );
});
