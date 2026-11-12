import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../cart/domain/cart_item.dart';

/// POST /api/orders (pago simulado, igual que la web):
///  - todos los beats sueltos van en una sola orden,
///  - cada paquete va en su propia orden.
class OrdersRepository {
  OrdersRepository(this._dio);

  final Dio _dio;

  /// [clave] identifica el cobro. Si la respuesta se pierde (el servidor cobró
  /// pero el teléfono no se enteró), reintentar con la misma clave devuelve la
  /// orden ya creada en lugar de cobrar otra vez.
  Future<void> buyBeats(List<String> beatIds, {required String clave}) => _post({'beats': beatIds}, clave);

  Future<void> buyPack(String packId, {required String clave}) => _post({'packId': packId}, clave);

  Future<void> _post(Map<String, dynamic> body, String clave) async {
    try {
      await _dio.post<void>('/orders', data: body, options: idempotente(clave));
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

/// Identifica el contenido de un cobro (independiente del orden): sirve para
/// reutilizar la misma clave de idempotencia si se reintenta ese mismo cobro.
String firmaDeGrupo(List<CartItem> grupo) {
  final ids = grupo.map((i) => '${i.tipo.name}:${i.itemId}').toList()..sort();
  return ids.join(',');
}

/// Agrupa el carrito en las peticiones que espera la API.
List<List<CartItem>> groupForCheckout(List<CartItem> items) => [
      if (items.any((i) => !i.isPack)) items.where((i) => !i.isPack).toList(),
      for (final p in items.where((i) => i.isPack)) [p],
    ];

final ordersRepositoryProvider =
    Provider<OrdersRepository>((ref) => OrdersRepository(ref.watch(dioProvider)));
