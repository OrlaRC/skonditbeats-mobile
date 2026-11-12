import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:workmanager/workmanager.dart';

import '../../core/config/env.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/secure_storage.dart';
import '../auth/presentation/auth_controller.dart';

/// Un ticket con algo nuevo para quien lo consulta.
class AvisoTicket {
  const AvisoTicket({required this.id, this.folio, this.asunto, this.nombre, this.actualizado});

  final String id;
  final int? folio;
  final String? asunto;
  final String? nombre;
  final String? actualizado;

  /// Identifica ESTA novedad: si el ticket vuelve a cambiar, es otro aviso.
  String get huella => '$id@$actualizado';

  factory AvisoTicket.fromJson(Map<String, dynamic> j) => AvisoTicket(
        id: j['id'] as String,
        folio: (j['folio'] as num?)?.toInt(),
        asunto: j['asunto'] as String?,
        nombre: j['nombre'] as String?,
        actualizado: j['updated_at'] as String?,
      );
}

class NoLeidos {
  const NoLeidos({this.total = 0, this.tickets = const []});
  final int total;
  final List<AvisoTicket> tickets;
}

// ── Notificaciones del sistema ────────────────────────────────────────────────

const _canal = AndroidNotificationDetails(
  'tickets',
  'Mensajes de soporte',
  channelDescription: 'Respuestas a tus tickets y mensajes nuevos',
  importance: Importance.high,
  priority: Priority.high,
  icon: 'ic_notification',
);

final _plugin = FlutterLocalNotificationsPlugin();
bool _iniciado = false;

/// Prepara las notificaciones. [alTocar] recibe el id del ticket del aviso tocado.
Future<void> iniciarNotificaciones({void Function(String ticketId)? alTocar}) async {
  if (_iniciado && alTocar == null) return;
  await _plugin.initialize(
    settings: const InitializationSettings(android: AndroidInitializationSettings('ic_notification')),
    onDidReceiveNotificationResponse: (r) {
      if (r.payload != null && r.payload!.isNotEmpty) alTocar?.call(r.payload!);
    },
  );
  _iniciado = true;
}

/// Ticket del aviso con el que se abrió la app (si la abrió una notificación).
Future<String?> ticketDeArranque() async {
  final d = await _plugin.getNotificationAppLaunchDetails();
  return (d?.didNotificationLaunchApp ?? false) ? d!.notificationResponse?.payload : null;
}

/// Android 13+ pide permiso para mostrar notificaciones.
Future<void> pedirPermisoNotificaciones() async {
  await _plugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();
}

const _claveVistos = 'skondit_avisos_vistos';

/// Muestra una notificación por cada novedad que no se haya avisado antes.
/// Lo usan la app abierta y la tarea en segundo plano; la lista de avisados se
/// guarda cifrada para que ninguno de los dos repita el mismo aviso.
@visibleForTesting
Future<int> notificarNuevos(List<AvisoTicket> tickets, FlutterSecureStorage storage, {required bool admin}) async {
  final previos = <String>{};
  try {
    previos.addAll((jsonDecode(await storage.read(key: _claveVistos) ?? '[]') as List).cast<String>());
  } catch (_) {}

  final nuevos = tickets.where((t) => !previos.contains(t.huella)).toList();
  for (final t in nuevos) {
    final folio = t.folio == null ? '' : ' #${t.folio}';
    await _plugin.show(
      id: t.id.hashCode & 0x7fffffff,
      title: admin ? 'Ticket$folio de ${t.nombre ?? 'un cliente'}' : 'Respondieron tu ticket$folio',
      body: t.asunto?.isNotEmpty == true ? t.asunto : 'Toca para ver la conversación',
      notificationDetails: const NotificationDetails(android: _canal),
      payload: t.id,
    );
  }
  // Solo se recuerdan las novedades vigentes, así la lista no crece sin fin.
  await storage.write(key: _claveVistos, value: jsonEncode(tickets.map((t) => t.huella).toList()));
  return nuevos.length;
}

NoLeidos _parsear(Map<String, dynamic>? data) => NoLeidos(
      total: (data?['total'] as num?)?.toInt() ?? 0,
      tickets: ((data?['tickets'] as List?) ?? []).cast<Map<String, dynamic>>().map(AvisoTicket.fromJson).toList(),
    );

// ── Con la app cerrada (WorkManager, cada ~15 min) ────────────────────────────

const _tarea = 'skondit.avisos';

@pragma('vm:entry-point')
void callbackAvisos() {
  Workmanager().executeTask((_, _) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      const storage = FlutterSecureStorage();
      final token = await storage.read(key: SecureStorage.tokenKey);
      final userRaw = await storage.read(key: SecureStorage.userKey);
      if (token == null || userRaw == null) return true;
      final rol = (jsonDecode(userRaw) as Map<String, dynamic>)['rol'] as String?;

      final res = await Dio(BaseOptions(
        baseUrl: Env.apiUrl,
        connectTimeout: Env.connectTimeout,
        receiveTimeout: Env.receiveTimeout,
      )).get<Map<String, dynamic>>('/contact/no-leidos', options: Options(headers: {'Authorization': 'Bearer $token'}));

      await iniciarNotificaciones();
      await notificarNuevos(_parsear(res.data).tickets, storage, admin: rol == 'ADMIN' || rol == 'SUPER_ADMIN');
    } catch (_) {
      // Sin red o sesión vencida: se intentará en la siguiente ronda.
    }
    return true;
  });
}

Future<void> programarAvisosEnSegundoPlano() async {
  if (defaultTargetPlatform != TargetPlatform.android) return;
  await Workmanager().initialize(callbackAvisos);
  await Workmanager().registerPeriodicTask(
    _tarea,
    _tarea,
    frequency: const Duration(minutes: 15), // mínimo que permite Android
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
}

Future<void> cancelarAvisosEnSegundoPlano() async {
  if (defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await Workmanager().cancelByUniqueName(_tarea);
  } catch (_) {}
}

// ── Con la app abierta ────────────────────────────────────────────────────────

/// Consulta los avisos cada 30 s mientras hay sesión. Alimenta las insignias
/// de la app y muestra la notificación de cada novedad.
class NoLeidosController extends Notifier<NoLeidos> {
  static const intervalo = Duration(seconds: 30);
  Timer? _timer;

  @override
  NoLeidos build() {
    final user = ref.watch(authControllerProvider.select((s) => s.user));
    _timer?.cancel();
    ref.onDispose(() => _timer?.cancel());
    if (user == null) {
      unawaited(cancelarAvisosEnSegundoPlano());
      return const NoLeidos();
    }
    unawaited(programarAvisosEnSegundoPlano().catchError((_) {}));
    _timer = Timer.periodic(intervalo, (_) => refrescar());
    Future.microtask(refrescar);
    return const NoLeidos();
  }

  Future<void> refrescar() async {
    final user = ref.read(authControllerProvider).user;
    if (user == null) return;
    try {
      final res = await ref.read(dioProvider).get<Map<String, dynamic>>('/contact/no-leidos');
      final nuevo = _parsear(res.data);
      state = nuevo;
      await iniciarNotificaciones();
      await notificarNuevos(nuevo.tickets, ref.read(rawSecureStorageProvider), admin: user.isAdmin);
    } catch (_) {
      // Sin red: se conserva lo último y se reintenta en la siguiente vuelta.
    }
  }

  /// Al abrir un ticket se marca como leído y se quita de las insignias.
  Future<void> marcarVisto(String ticketId) async {
    state = NoLeidos(
      total: (state.total - (state.tickets.any((t) => t.id == ticketId) ? 1 : 0)).clamp(0, 1 << 30),
      tickets: state.tickets.where((t) => t.id != ticketId).toList(),
    );
    try {
      await ref.read(dioProvider).put<void>('/contact/$ticketId/visto');
    } on DioException catch (e) {
      // No es grave: el aviso volverá a aparecer y se marcará la próxima vez.
      debugPrint('No se pudo marcar el ticket como visto: ${ApiException.fromDio(e).message}');
    }
  }
}

final noLeidosProvider = NotifierProvider<NoLeidosController, NoLeidos>(NoLeidosController.new);
