import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import '../../../core/network/api_client.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../auth/presentation/app_lock_controller.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../catalog/domain/beat.dart';
import '../../catalog/presentation/widgets/cover_image.dart';
import '../../catalog/presentation/widgets/state_views.dart';
import '../../transfers/domain/transferencia.dart';
import '../../transfers/transfer_manager.dart';
import '../data/admin_repository.dart';

/// Límites del documento del proyecto.
const maxAudioBytes = 10 * 1024 * 1024;
const maxPortadaBytes = 2 * 1024 * 1024;
const mimeAudio = {'.mp3': 'audio/mpeg', '.m4a': 'audio/mp4', '.aac': 'audio/aac'};
const mimeImagen = {'.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.png': 'image/png', '.webp': 'image/webp'};

/// Valida un archivo antes de encolarlo. Devuelve el MIME o lanza [ApiException].
String validarArchivo(String ruta, int bytes, {required bool audio}) {
  final ext = p.extension(ruta).toLowerCase();
  final mime = (audio ? mimeAudio : mimeImagen)[ext];
  if (mime == null) {
    throw ApiException(audio ? 'Formato no permitido. Usa MP3, M4A o AAC.' : 'Formato no permitido. Usa JPG, PNG o WebP.');
  }
  final max = audio ? maxAudioBytes : maxPortadaBytes;
  if (bytes > max) {
    throw ApiException('El archivo pesa ${formatoBytes(bytes)}; el máximo es ${formatoBytes(max)}.');
  }
  return mime;
}

/// Gestor de beats: catálogo paginado con búsqueda, alta, edición y baja.
class BeatsAdminScreen extends ConsumerStatefulWidget {
  const BeatsAdminScreen({super.key});

  @override
  ConsumerState<BeatsAdminScreen> createState() => _BeatsAdminScreenState();
}

class _BeatsAdminScreenState extends ConsumerState<BeatsAdminScreen> {
  final _scroll = ScrollController();
  Timer? _debounce;
  BeatsFilter _filtro = const BeatsFilter();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 600) ref.read(beatsPagerProvider(_filtro).notifier).cargarMas();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _abrirFormulario([Beat? beat]) async {
    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (_) => BeatForm(beat: beat, generos: ref.read(beatsPagerProvider(_filtro)).value?.generos ?? const []),
    );
    if (guardado == true) ref.invalidate(beatsPagerProvider);
  }

  Future<void> _eliminar(Beat b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar beat'),
        content: Text('"${b.nombre}" dejará de venderse. Quien ya lo compró lo conserva.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(adminRepositoryProvider).deleteBeat(b.id);
      ref.invalidate(beatsPagerProvider);
      ref.invalidate(novedadesProvider);
      if (mounted) showAppSnack(context, 'Beat eliminado', type: SnackType.success);
    } on ApiException catch (e) {
      if (mounted) showAppSnack(context, e.message, type: SnackType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lista = ref.watch(beatsPagerProvider(_filtro));
    final enCurso = ref.watch(transferenciasEnCursoProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestor de beats'),
        actions: [
          IconButton(
            tooltip: 'Transferencias',
            onPressed: () => context.push(Routes.transferencias),
            icon: Badge(
              isLabelVisible: enCurso > 0,
              label: Text('$enCurso'),
              backgroundColor: AppColors.primary,
              textColor: Colors.black,
              child: const Icon(Icons.swap_vert),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormulario(),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo beat'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              textInputAction: TextInputAction.search,
              onChanged: (t) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 400), () {
                  if (mounted) setState(() => _filtro = _filtro.copyWith(search: t));
                });
              },
              decoration: const InputDecoration(
                hintText: 'Buscar por nombre o género',
                prefixIcon: Icon(Icons.search),
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.primary,
              onRefresh: () => ref.refresh(beatsPagerProvider(_filtro).future).then((_) {}, onError: (_) {}),
              child: lista.when(
                skipLoadingOnRefresh: true,
                loading: () => const LoadingList(),
                error: (e, _) => ErrorView(
                  message: e is ApiException ? e.message : 'No se pudo cargar el catálogo',
                  onRetry: () => ref.invalidate(beatsPagerProvider(_filtro)),
                ),
                data: (l) => l.beats.isEmpty
                    ? const EmptyView(icon: Icons.library_music_outlined, title: 'Sin beats', message: 'Agrega el primero con el botón de abajo')
                    : ListView.separated(
                        controller: _scroll,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                        itemCount: l.beats.length + 1,
                        separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.border),
                        itemBuilder: (_, i) {
                          if (i == l.beats.length) {
                            return PieDeLista(
                              cargando: l.cargandoMas,
                              hayMas: l.hayMas,
                              total: l.total,
                              error: l.errorAlCargarMas,
                              onReintentar: () => ref.read(beatsPagerProvider(_filtro).notifier).cargarMas(),
                            );
                          }
                          final b = l.beats[i];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                            leading: CoverImage(url: b.imagenUrl, size: 52),
                            title: Text(b.nombre, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              '${b.genero} · ${b.bpm} BPM · ${formatMoney(b.precio)}${b.tieneAudio ? '' : ' · sin audio'}',
                              style: TextStyle(color: b.tieneAudio ? AppColors.textMuted : AppColors.error),
                            ),
                            onTap: () => _abrirFormulario(b),
                            trailing: IconButton(
                              tooltip: 'Eliminar',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _eliminar(b),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Alta o edición de un beat. Los datos se guardan primero; el audio y la
/// portada se suben después en segundo plano con carga reanudable, así un corte
/// de red no obliga a capturar todo otra vez.
class BeatForm extends ConsumerStatefulWidget {
  const BeatForm({super.key, this.beat, this.generos = const []});

  final Beat? beat;
  final List<String> generos;

  @override
  ConsumerState<BeatForm> createState() => _BeatFormState();
}

class _BeatFormState extends ConsumerState<BeatForm> {
  final _form = GlobalKey<FormState>();
  late final _nombre = TextEditingController(text: widget.beat?.nombre);
  late final _genero = TextEditingController(text: widget.beat?.genero);
  late final _bpm = TextEditingController(text: widget.beat?.bpm.toString());
  late final _precio = TextEditingController(text: widget.beat?.precio.toString());
  late final _descripcion = TextEditingController(text: widget.beat?.descripcion);

  File? _audio;
  File? _portada;
  bool _guardando = false;

  /// Una clave por alta: si se reintenta tras un corte, no se crea otro beat.
  final _clave = nuevaClaveIdempotencia();

  @override
  void dispose() {
    for (final c in [_nombre, _genero, _bpm, _precio, _descripcion]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _elegirAudio() async {
    try {
      final f = await ref.read(appLockProvider.notifier).runWithoutLock(
            () => FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['mp3', 'm4a', 'aac']),
          );
      final ruta = f?.path;
      if (ruta == null) return;
      final file = File(ruta);
      validarArchivo(ruta, await file.length(), audio: true);
      setState(() => _audio = file);
    } on ApiException catch (e) {
      if (mounted) showAppSnack(context, e.message, type: SnackType.error);
    } on PlatformException {
      if (mounted) showAppSnack(context, 'No se pudo abrir el selector de archivos', type: SnackType.error);
    }
  }

  Future<void> _elegirPortada(ImageSource source) async {
    try {
      final x = await ref.read(appLockProvider.notifier).runWithoutLock(
            () => ImagePicker().pickImage(source: source, maxWidth: 1080, maxHeight: 1080, imageQuality: 85),
          );
      if (x == null) return;
      final file = File(x.path);
      validarArchivo(x.path, await file.length(), audio: false);
      setState(() => _portada = file);
    } on ApiException catch (e) {
      if (mounted) showAppSnack(context, e.message, type: SnackType.error);
    } on PlatformException {
      if (mounted) showAppSnack(context, 'Da permiso de cámara o fotos en los ajustes', type: SnackType.error);
    }
  }

  Future<void> _guardar() async {
    FocusScope.of(context).unfocus();
    if (_guardando || !_form.currentState!.validate()) return;
    setState(() => _guardando = true);

    final datos = BeatInput(
      nombre: _nombre.text,
      genero: _genero.text,
      bpm: int.parse(_bpm.text.trim()),
      precio: num.parse(_precio.text.trim()),
      descripcion: _descripcion.text,
    );
    final repo = ref.read(adminRepositoryProvider);
    try {
      final beat = widget.beat == null ? await repo.createBeat(datos, clave: _clave) : await repo.updateBeat(widget.beat!.id, datos);

      final cola = ref.read(transferManagerProvider.notifier);
      if (_audio != null) {
        await cola.subir(
          archivo: _audio!,
          bucket: 'beats-audio',
          mime: validarArchivo(_audio!.path, await _audio!.length(), audio: true),
          titulo: 'Audio de "${beat.nombre}"',
          destino: DestinoSubida.beat(beat.id, audio: true),
        );
      }
      if (_portada != null) {
        await cola.subir(
          archivo: _portada!,
          bucket: 'beats-images',
          mime: validarArchivo(_portada!.path, await _portada!.length(), audio: false),
          titulo: 'Portada de "${beat.nombre}"',
          destino: DestinoSubida.beat(beat.id, audio: false),
        );
      }
      ref.invalidate(novedadesProvider);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      final subiendo = _audio != null || _portada != null;
      showAppSnack(
        context,
        subiendo
            ? 'Beat guardado. Los archivos se suben en segundo plano y continúan si cambias de red.'
            : 'Beat guardado',
        type: SnackType.success,
      );
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      HapticFeedback.heavyImpact();
      if (mounted) {
        showAppSnack(
          context,
          e.sinRed ? '${e.message} Vuelve a tocar Guardar: no se duplicará.' : e.message,
          type: SnackType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editando = widget.beat != null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(editando ? 'Editar beat' : 'Nuevo beat', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nombre,
                  enabled: !_guardando,
                  maxLength: 150,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Nombre', counterText: ''),
                  validator: (v) => (v == null || v.trim().length < 2) ? 'Mínimo 2 caracteres' : null,
                ),
                const SizedBox(height: 12),
                Autocomplete<String>(
                  initialValue: TextEditingValue(text: _genero.text),
                  optionsBuilder: (v) => widget.generos.where((g) => g.toLowerCase().contains(v.text.toLowerCase())),
                  onSelected: (g) => _genero.text = g,
                  fieldViewBuilder: (_, controller, foco, _) => TextFormField(
                    controller: controller,
                    focusNode: foco,
                    enabled: !_guardando,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (v) => _genero.text = v,
                    decoration: const InputDecoration(labelText: 'Género'),
                    validator: (v) => (v == null || v.trim().length < 2) ? 'Escribe el género' : null,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _bpm,
                        enabled: !_guardando,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(labelText: 'BPM'),
                        validator: (v) {
                          final n = int.tryParse(v ?? '');
                          return (n == null || n < 1 || n > 299) ? 'Entre 1 y 299' : null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _precio,
                        enabled: !_guardando,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                        decoration: const InputDecoration(labelText: 'Precio (MXN)'),
                        validator: (v) {
                          final n = num.tryParse(v ?? '');
                          return (n == null || n < 0) ? 'Precio no válido' : null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descripcion,
                  enabled: !_guardando,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 500,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Descripción (opcional)'),
                ),
                const SizedBox(height: 8),
                _ArchivoTile(
                  icono: Icons.audiotrack,
                  titulo: _audio != null
                      ? p.basename(_audio!.path)
                      : (widget.beat?.tieneAudio ?? false)
                          ? 'Audio actual (toca para reemplazar)'
                          : 'Elegir audio (MP3, máx. 10 MB)',
                  listo: _audio != null || (widget.beat?.tieneAudio ?? false),
                  onTap: _guardando ? null : _elegirAudio,
                ),
                _ArchivoTile(
                  icono: Icons.image_outlined,
                  titulo: _portada != null
                      ? p.basename(_portada!.path)
                      : widget.beat?.imagenUrl != null
                          ? 'Portada actual (toca para reemplazar)'
                          : 'Elegir portada (JPG/PNG/WebP, máx. 2 MB)',
                  listo: _portada != null || widget.beat?.imagenUrl != null,
                  onTap: _guardando
                      ? null
                      : () async {
                          final src = await showModalBottomSheet<ImageSource>(
                            context: context,
                            backgroundColor: AppColors.surface,
                            builder: (ctx) => SafeArea(
                              child: Column(mainAxisSize: MainAxisSize.min, children: [
                                ListTile(
                                  leading: const Icon(Icons.photo_camera_outlined),
                                  title: const Text('Tomar foto'),
                                  onTap: () => Navigator.pop(ctx, ImageSource.camera),
                                ),
                                ListTile(
                                  leading: const Icon(Icons.photo_library_outlined),
                                  title: const Text('Galería'),
                                  onTap: () => Navigator.pop(ctx, ImageSource.gallery),
                                ),
                              ]),
                            ),
                          );
                          if (src != null) await _elegirPortada(src);
                        },
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _guardando ? null : _guardar,
                  icon: _guardando
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black))
                      : const Icon(Icons.save_outlined),
                  label: Text(_guardando ? 'Guardando...' : 'Guardar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ArchivoTile extends StatelessWidget {
  const _ArchivoTile({required this.icono, required this.titulo, required this.listo, required this.onTap});

  final IconData icono;
  final String titulo;
  final bool listo;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icono, color: AppColors.primary),
        title: Text(titulo, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Icon(listo ? Icons.check_circle : Icons.upload_file, color: listo ? AppColors.success : AppColors.textMuted),
        onTap: onTap,
      );
}
