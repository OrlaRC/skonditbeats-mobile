import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

bool _hayRed(List<ConnectivityResult> r) => r.any((c) => c != ConnectivityResult.none);

/// true mientras el teléfono tiene alguna red (Wi-Fi, datos, Ethernet).
/// Cambia al entrar o salir de una red: con eso se muestra el aviso de "sin
/// conexión" y se reanudan las subidas y descargas pendientes.
final conectividadProvider = StreamProvider<bool>((ref) async* {
  final c = Connectivity();
  yield _hayRed(await c.checkConnectivity());
  yield* c.onConnectivityChanged.map(_hayRed);
});
