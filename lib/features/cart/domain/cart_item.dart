import '../../catalog/domain/beat.dart';
import '../../catalog/domain/pack.dart';

enum CartItemType { beat, pack }

/// Entidad: un artículo del carrito (beat suelto o paquete).
class CartItem {
  const CartItem({
    required this.tipo,
    required this.itemId,
    required this.nombre,
    required this.detalle,
    required this.precio,
    required this.beatIds,
    required this.agregado,
    this.imagenUrl,
  });

  final CartItemType tipo;
  final String itemId;
  final String nombre;

  /// "Trap · 140 BPM" o "3 beats".
  final String detalle;
  final num precio;
  final String? imagenUrl;

  /// Beats que incluye: el propio beat, o los del paquete.
  final List<String> beatIds;
  final DateTime agregado;

  bool get isPack => tipo == CartItemType.pack;

  factory CartItem.fromBeat(Beat b) => CartItem(
        tipo: CartItemType.beat,
        itemId: b.id,
        nombre: b.nombre,
        detalle: '${b.genero} · ${b.bpm} BPM',
        precio: b.precio,
        imagenUrl: b.imagenUrl,
        beatIds: [b.id],
        agregado: DateTime.now(),
      );

  factory CartItem.fromPack(Pack p) => CartItem(
        tipo: CartItemType.pack,
        itemId: p.id,
        nombre: p.nombre,
        detalle: '${p.beats.length} beats',
        precio: p.precio,
        imagenUrl: p.imagenUrl,
        beatIds: p.beats.map((b) => b.id).toList(),
        agregado: DateTime.now(),
      );

  factory CartItem.fromMap(Map<String, Object?> m) => CartItem(
        tipo: m['tipo'] == 'pack' ? CartItemType.pack : CartItemType.beat,
        itemId: m['item_id'] as String,
        nombre: m['nombre'] as String,
        detalle: m['detalle'] as String,
        precio: m['precio'] as num,
        imagenUrl: m['imagen_url'] as String?,
        beatIds: (m['beat_ids'] as String).split(',').where((s) => s.isNotEmpty).toList(),
        agregado: DateTime.parse(m['agregado'] as String),
      );

  Map<String, Object?> toMap(String userId) => {
        'user_id': userId,
        'tipo': tipo.name,
        'item_id': itemId,
        'nombre': nombre,
        'detalle': detalle,
        'precio': precio.toDouble(),
        'imagen_url': imagenUrl,
        'beat_ids': beatIds.join(','),
        'agregado': agregado.toIso8601String(),
      };
}
