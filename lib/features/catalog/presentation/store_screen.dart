import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../data/catalog_repository.dart';
import '../domain/beat.dart';
import 'widgets/beat_tile.dart';
import 'widgets/state_views.dart';

/// Tienda de beats: búsqueda, filtro por género y filtros de BPM/precio.
class StoreScreen extends ConsumerStatefulWidget {
  const StoreScreen({super.key});

  @override
  ConsumerState<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends ConsumerState<StoreScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;
  BeatsFilter _filter = const BeatsFilter();
  List<String> _generos = const [];

  @override
  void initState() {
    super.initState();
    // Al acercarse al final de la lista se pide la página siguiente.
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 600) ref.read(beatsPagerProvider(_filter).notifier).cargarMas();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onSearch(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _filter = _filter.copyWith(search: text));
    });
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<BeatsFilter>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (_) => _FiltersSheet(initial: _filter),
    );
    if (result != null) setState(() => _filter = result);
  }

  @override
  Widget build(BuildContext context) {
    final page = ref.watch(beatsPagerProvider(_filter));
    // Se guardan los géneros para que los chips no desaparezcan al filtrar.
    if (page.value case final p? when p.generos.isNotEmpty) _generos = p.generos;

    return Scaffold(
      appBar: AppBar(title: const Text('Tienda de beats')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    onChanged: _onSearch,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Buscar por nombre o género',
                      prefixIcon: const Icon(Icons.search),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Limpiar búsqueda',
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _search.clear();
                                _onSearch('');
                              },
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Filtros',
                  onPressed: _openFilters,
                  icon: Badge(
                    isLabelVisible: _filter.tieneFiltrosAvanzados,
                    backgroundColor: AppColors.primary,
                    smallSize: 8,
                    child: const Icon(Icons.tune),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final g in [null, ..._generos])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(g ?? 'Todos'),
                      selected: _filter.genero == g,
                      selectedColor: AppColors.primary,
                      labelStyle: TextStyle(
                        color: _filter.genero == g ? Colors.black : Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _filter = _filter.copyWith(genero: () => g)),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.primary,
              onRefresh: () async {
                ref.invalidate(ownedBeatIdsProvider);
                return ref.refresh(beatsPagerProvider(_filter).future).then((_) {}, onError: (_) {});
              },
              child: page.when(
                skipLoadingOnRefresh: true,
                loading: () => const LoadingList(),
                error: (e, _) => ErrorView(
                  message: e is ApiException ? e.message : 'No se pudieron cargar los beats',
                  onRetry: () => ref.invalidate(beatsPagerProvider(_filter)),
                ),
                data: (p) => p.beats.isEmpty
                    ? const EmptyView(
                        icon: Icons.search_off,
                        title: 'Sin resultados',
                        message: 'Prueba con otra búsqueda o quita los filtros',
                      )
                    : ListView.separated(
                        controller: _scroll,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                        // Un renglón extra al final: cargando, error o fin de lista.
                        itemCount: p.beats.length + 1,
                        separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.border),
                        itemBuilder: (_, i) => i < p.beats.length
                            ? BeatTile(beat: p.beats[i], queue: p.beats)
                            : PieDeLista(
                                cargando: p.cargandoMas,
                                error: p.errorAlCargarMas,
                                hayMas: p.hayMas,
                                total: p.total,
                                onReintentar: () => ref.read(beatsPagerProvider(_filter).notifier).cargarMas(),
                              ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FiltersSheet extends StatefulWidget {
  const _FiltersSheet({required this.initial});

  final BeatsFilter initial;

  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  static const _bpmMin = 60.0, _bpmMax = 200.0, _precioMax = 2000.0;

  late RangeValues _bpm = RangeValues(
    (widget.initial.bpmMin ?? _bpmMin).toDouble(),
    (widget.initial.bpmMax ?? _bpmMax).toDouble(),
  );
  late double _precio = (widget.initial.precioMax ?? _precioMax).toDouble();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Filtros', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 20),
            Text('Tempo: ${_bpm.start.round()} – ${_bpm.end.round()} BPM'),
            RangeSlider(
              values: _bpm,
              min: _bpmMin,
              max: _bpmMax,
              divisions: 28,
              activeColor: AppColors.primary,
              labels: RangeLabels('${_bpm.start.round()}', '${_bpm.end.round()}'),
              onChanged: (v) => setState(() => _bpm = v),
            ),
            const SizedBox(height: 8),
            Text(_precio >= _precioMax ? 'Precio: cualquiera' : 'Precio máximo: ${formatMoney(_precio)}'),
            Slider(
              value: _precio,
              min: 100,
              max: _precioMax,
              divisions: 19,
              activeColor: AppColors.primary,
              label: formatMoney(_precio, currency: false),
              onChanged: (v) => setState(() => _precio = v),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(
                      context,
                      widget.initial.copyWith(bpmMin: () => null, bpmMax: () => null, precioMax: () => null),
                    ),
                    child: const Text('Quitar filtros'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(
                      context,
                      widget.initial.copyWith(
                        bpmMin: () => _bpm.start <= _bpmMin ? null : _bpm.start.round(),
                        bpmMax: () => _bpm.end >= _bpmMax ? null : _bpm.end.round(),
                        precioMax: () => _precio >= _precioMax ? null : _precio.round(),
                      ),
                    ),
                    child: const Text('Aplicar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
