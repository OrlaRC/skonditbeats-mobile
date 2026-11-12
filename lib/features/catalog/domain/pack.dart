import '../../../core/utils/money.dart';
import 'beat.dart';

class Pack {
  const Pack({
    required this.id,
    required this.nombre,
    required this.precio,
    required this.beats,
    this.descripcion,
    this.imagenUrl,
  });

  final String id;
  final String nombre;
  final num precio;
  final List<Beat> beats;
  final String? descripcion;
  final String? imagenUrl;

  /// Lo que costarían los beats comprados por separado.
  num get precioSeparado => beats.fold<num>(0, (s, b) => s + b.precio);
  num get ahorro => (precioSeparado - precio).clamp(0, double.infinity);

  factory Pack.fromJson(Map<String, dynamic> j) => Pack(
        id: j['id'] as String,
        nombre: (j['nombre'] as String?) ?? 'Paquete',
        precio: parseNum(j['precio']),
        descripcion: j['descripcion'] as String?,
        imagenUrl: (j['imagen_url'] as String?)?.trim().isEmpty ?? true ? null : j['imagen_url'] as String,
        beats: ((j['pack_beats'] as List?) ?? [])
            .map((pb) => (pb as Map)['beats'])
            .whereType<Map<String, dynamic>>()
            .map(Beat.fromJson)
            .toList(),
      );
}
