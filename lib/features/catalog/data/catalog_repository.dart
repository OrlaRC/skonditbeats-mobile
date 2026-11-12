import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/beat.dart';
import '../domain/pack.dart';

/// Catálogo: GET /api/beats, GET /api/packs y los beats que ya compró el usuario.
class CatalogRepository {
  CatalogRepository(this._dio);

  final Dio _dio;

  static const tamanoPagina = 20;

  /// Una página del catálogo. Antes se pedía el catálogo completo en cada
  /// pantalla; ahora la API devuelve solo [limit] beats y el total del filtro.
  Future<BeatsPage> getBeats(BeatsFilter filter, {int page = 1, int limit = tamanoPagina}) async {
    final data = await _get('/beats', query: {...filter.toQuery(), 'limit': limit, 'page': page});
    final beats = (data['beats'] as List).cast<Map<String, dynamic>>().map(Beat.fromJson).toList();
    return BeatsPage(
      beats: beats,
      generos: ((data['generos'] as List?) ?? []).cast<String>(),
      total: (data['total'] as num?)?.toInt() ?? beats.length,
    );
  }

  Future<List<Pack>> getPacks() async {
    final data = await _get('/packs');
    return (data['packs'] as List).cast<Map<String, dynamic>>().map(Pack.fromJson).toList();
  }

  /// IDs de beats que el usuario ya tiene (sueltos o dentro de paquetes).
  Future<Set<String>> getOwnedBeatIds() async {
    final data = await _get('/orders/mis-compras');
    final ids = <String>{};
    for (final order in (data['orders'] as List).cast<Map<String, dynamic>>()) {
      for (final item in ((order['order_items'] as List?) ?? []).cast<Map<String, dynamic>>()) {
        final beat = item['beats'] as Map<String, dynamic>?;
        if (beat?['id'] case final String id) ids.add(id);
      }
    }
    return ids;
  }

  Future<Map<String, dynamic>> _get(String path, {Map<String, dynamic>? query}) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(path, queryParameters: query);
      return res.data ?? {};
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final catalogRepositoryProvider =
    Provider<CatalogRepository>((ref) => CatalogRepository(ref.watch(dioProvider)));

/// Los beats cargados hasta ahora de una búsqueda, página por página.
class BeatsLista {
  const BeatsLista({
    required this.beats,
    required this.generos,
    required this.total,
    this.cargandoMas = false,
    this.errorAlCargarMas,
  });

  final List<Beat> beats;
  final List<String> generos;
  final int total;
  final bool cargandoMas;

  /// Falló la carga de la página siguiente; lo ya mostrado se conserva.
  final String? errorAlCargarMas;

  bool get hayMas => beats.length < total;
}

/// Catálogo con scroll infinito: trae la primera página y pide la siguiente al
/// acercarse al final de la lista. Lo usan la tienda y el gestor de beats.
class BeatsPager extends AsyncNotifier<BeatsLista> {
  BeatsPager(this.filter);

  final BeatsFilter filter;
  int _pagina = 1;

  @override
  Future<BeatsLista> build() async {
    _pagina = 1;
    final p = await ref.watch(catalogRepositoryProvider).getBeats(filter);
    return BeatsLista(beats: p.beats, generos: p.generos, total: p.total);
  }

  Future<void> cargarMas() async {
    final actual = state.value;
    if (actual == null || actual.cargandoMas || !actual.hayMas) return;

    state = AsyncData(BeatsLista(beats: actual.beats, generos: actual.generos, total: actual.total, cargandoMas: true));
    try {
      final p = await ref.read(catalogRepositoryProvider).getBeats(filter, page: _pagina + 1);
      _pagina++;
      // Si entró un beat nuevo mientras tanto, la página siguiente puede repetir uno.
      final vistos = actual.beats.map((b) => b.id).toSet();
      state = AsyncData(BeatsLista(
        beats: [...actual.beats, ...p.beats.where((b) => vistos.add(b.id))],
        generos: p.generos.isEmpty ? actual.generos : p.generos,
        // Sin beats nuevos se corta la paginación para no pedir en bucle.
        total: p.beats.isEmpty ? actual.beats.length : p.total,
      ));
    } on ApiException catch (e) {
      state = AsyncData(BeatsLista(
        beats: actual.beats,
        generos: actual.generos,
        total: actual.total,
        errorAlCargarMas: e.message,
      ));
    }
  }
}

final beatsPagerProvider =
    AsyncNotifierProvider.autoDispose.family<BeatsPager, BeatsLista, BeatsFilter>(BeatsPager.new);

/// Los 8 beats más recientes para el inicio (una petición pequeña, no el catálogo).
final novedadesProvider = FutureProvider.autoDispose<List<Beat>>(
  (ref) async => (await ref.watch(catalogRepositoryProvider).getBeats(const BeatsFilter(), limit: 8)).beats,
);

final packsProvider = FutureProvider.autoDispose<List<Pack>>(
  (ref) => ref.watch(catalogRepositoryProvider).getPacks(),
);

/// Se recarga al cambiar de usuario y después de cada compra (invalidate).
final ownedBeatIdsProvider = FutureProvider<Set<String>>((ref) {
  final userId = ref.watch(authControllerProvider.select((s) => s.user?.id));
  if (userId == null) return Future.value(<String>{});
  return ref.watch(catalogRepositoryProvider).getOwnedBeatIds();
});
