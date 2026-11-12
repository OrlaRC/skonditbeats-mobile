import '../../../core/utils/money.dart';

class Beat {
  const Beat({
    required this.id,
    required this.nombre,
    required this.genero,
    required this.bpm,
    required this.precio,
    this.imagenUrl,
    this.audioUrl,
    this.descripcion,
  });

  final String id;
  final String nombre;
  final String genero;
  final int bpm;
  final num precio;
  final String? imagenUrl;
  final String? audioUrl;
  final String? descripcion;

  bool get tieneAudio => audioUrl != null && audioUrl!.isNotEmpty;

  factory Beat.fromJson(Map<String, dynamic> j) => Beat(
        id: j['id'] as String,
        nombre: (j['nombre'] as String?) ?? 'Sin nombre',
        genero: (j['genero'] as String?) ?? '',
        bpm: parseNum(j['bpm']).toInt(),
        precio: parseNum(j['precio']),
        imagenUrl: _url(j['imagen_url']),
        audioUrl: _url(j['audio_url']),
        descripcion: j['descripcion'] as String?,
      );

  static String? _url(Object? v) {
    final s = v as String?;
    return (s == null || s.trim().isEmpty) ? null : s;
  }
}

class BeatsPage {
  const BeatsPage({required this.beats, required this.generos, required this.total});
  final List<Beat> beats;
  final List<String> generos;

  /// Total de beats que cumplen el filtro (no solo los de esta página).
  final int total;
}

/// Filtros de la tienda (mismos parámetros que acepta GET /api/beats).
class BeatsFilter {
  const BeatsFilter({this.search = '', this.genero, this.bpmMin, this.bpmMax, this.precioMax});

  final String search;
  final String? genero;
  final int? bpmMin;
  final int? bpmMax;
  final int? precioMax;

  bool get tieneFiltrosAvanzados => bpmMin != null || bpmMax != null || precioMax != null;

  BeatsFilter copyWith({
    String? search,
    String? Function()? genero,
    int? Function()? bpmMin,
    int? Function()? bpmMax,
    int? Function()? precioMax,
  }) =>
      BeatsFilter(
        search: search ?? this.search,
        genero: genero != null ? genero() : this.genero,
        bpmMin: bpmMin != null ? bpmMin() : this.bpmMin,
        bpmMax: bpmMax != null ? bpmMax() : this.bpmMax,
        precioMax: precioMax != null ? precioMax() : this.precioMax,
      );

  Map<String, dynamic> toQuery() => {
        if (search.trim().isNotEmpty) 'search': search.trim(),
        'genero': ?genero,
        'bpm_min': ?bpmMin,
        'bpm_max': ?bpmMax,
        'precio_max': ?precioMax,
      };

  @override
  bool operator ==(Object other) =>
      other is BeatsFilter &&
      other.search == search &&
      other.genero == genero &&
      other.bpmMin == bpmMin &&
      other.bpmMax == bpmMax &&
      other.precioMax == precioMax;

  @override
  int get hashCode => Object.hash(search, genero, bpmMin, bpmMax, precioMax);
}
