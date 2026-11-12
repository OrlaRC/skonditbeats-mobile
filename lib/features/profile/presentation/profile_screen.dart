import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../activity/data/acceso.dart';
import '../../activity/data/acceso_dao.dart';
import '../../auth/presentation/app_lock_controller.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/roles.dart';
import '../../transfers/transfer_manager.dart';
import '../data/profile_repository.dart';

final profileProvider = FutureProvider.autoDispose<Profile>(
  (ref) => ref.watch(profileRepositoryProvider).fetch(),
);

final accesosProvider = FutureProvider.autoDispose<List<Acceso>>((ref) {
  final email = ref.watch(authControllerProvider.select((s) => s.user?.email));
  if (email == null) return Future.value(const []);
  return ref.watch(accesoDaoProvider).listarPorEmail(email);
});

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _subiendo = false;

  Future<void> _cambiarFoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tomar foto'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Elegir de la galería'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    try {
      // La cámara, la galería y el recorte mandan la app a segundo plano: no
      // deben bloquearla.
      final foto = await ref.read(appLockProvider.notifier).runWithoutLock(() async {
        final picked = await ImagePicker().pickImage(
          source: source,
          maxWidth: 1080,
          maxHeight: 1080,
          preferredCameraDevice: CameraDevice.front,
        );
        if (picked == null) return null;
        return ImageCropper().cropImage(
          sourcePath: picked.path,
          aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
          maxWidth: 512,
          maxHeight: 512,
          compressQuality: 80,
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: 'Recortar foto',
              toolbarColor: Colors.black,
              toolbarWidgetColor: Colors.white,
              activeControlsWidgetColor: AppColors.primary,
              cropStyle: CropStyle.circle,
              lockAspectRatio: true,
            ),
            IOSUiSettings(
              title: 'Recortar foto',
              cropStyle: CropStyle.circle,
              aspectRatioLockEnabled: true,
              resetAspectRatioEnabled: false,
            ),
          ],
        );
      });
      if (foto == null || !mounted) return;

      // Se encola en la subida reanudable: si se corta la red, continúa sola al
      // reconectarse y al terminar actualiza el perfil.
      final archivo = File(foto.path);
      final mime = await ProfileRepository.validarFoto(archivo);
      await ref.read(transferManagerProvider.notifier).subir(
            archivo: archivo,
            bucket: 'avatars',
            mime: mime,
            titulo: 'Foto de perfil',
            destino: DestinoSubida.fotoPerfil(),
          );

      HapticFeedback.mediumImpact();
      if (mounted) showAppSnack(context, 'Subiendo tu foto…', type: SnackType.info);
    } on ApiException catch (e) {
      HapticFeedback.heavyImpact();
      if (mounted) showAppSnack(context, e.message, type: SnackType.error);
    } on PlatformException catch (e) {
      if (mounted) {
        final msg = e.code.contains('access_denied')
            ? 'Da permiso de cámara o fotos en los ajustes del teléfono'
            : 'No se pudo abrir la ${source == ImageSource.camera ? 'cámara' : 'galería'}';
        showAppSnack(context, msg, type: SnackType.error);
      }
    } finally {
      if (mounted) setState(() => _subiendo = false);
    }
  }

  Future<void> _borrarHistorial(String email) async {
    await ref.read(accesoDaoProvider).eliminarPorEmail(email);
    ref.invalidate(accesosProvider);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final profile = ref.watch(profileProvider);
    // La foto se está subiendo mientras haya una transferencia de perfil en curso.
    final subiendoFoto = ref.watch(transferManagerProvider
        .select((l) => l.any((t) => t.destino?['accion'] == 'perfil_foto' && t.enCurso)));
    final cargandoFoto = _subiendo || subiendoFoto;
    final accesos = ref.watch(accesosProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Mi perfil')),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async {
          ref.invalidate(profileProvider);
          ref.invalidate(accesosProvider);
          try {
            await ref.read(profileProvider.future);
          } catch (_) {
            // El error ya se muestra en la sección de datos.
          }
        },
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: _Avatar(
                url: user?.fotoUrl,
                nombre: user?.nombre ?? '',
                cargando: cargandoFoto,
                onTap: cargandoFoto ? null : _cambiarFoto,
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: cargandoFoto ? null : _cambiarFoto,
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: Text(subiendoFoto ? 'Subiendo foto…' : 'Cambiar foto'),
              ),
            ),
            Center(
              child: TextButton.icon(
                onPressed: () => context.push(Routes.transferencias),
                icon: const Icon(Icons.swap_vert, size: 18),
                label: const Text('Subidas y descargas'),
              ),
            ),
            const SizedBox(height: 16),
            profile.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
              ),
              error: (e, _) => _Seccion(
                titulo: 'Mis datos',
                children: [
                  ListTile(
                    leading: const Icon(Icons.cloud_off_outlined, color: AppColors.error),
                    title: Text(e is ApiException ? e.message : 'No se pudo cargar el perfil'),
                    trailing: TextButton(
                      onPressed: () => ref.invalidate(profileProvider),
                      child: const Text('Reintentar'),
                    ),
                  ),
                ],
              ),
              data: (p) => _Seccion(
                titulo: 'Mis datos',
                children: [
                  _Dato(Icons.person_outline, 'Nombre', p.nombre),
                  if (p.username != null) _Dato(Icons.alternate_email, 'Nombre artístico', p.username!),
                  _Dato(Icons.mail_outline, 'Correo', p.email),
                  if (p.telefono != null) _Dato(Icons.phone_outlined, 'Teléfono', p.telefono!),
                  if (p.edad != null) _Dato(Icons.cake_outlined, 'Edad', '${p.edad} años'),
                  _Dato(Icons.badge_outlined, 'Rol', Rol.desde(p.rol).etiqueta),
                  if (p.fechaRegistro != null)
                    _Dato(Icons.event_outlined, 'Miembro desde', _fecha(p.fechaRegistro!, conHora: false)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _Seccion(
              titulo: 'Accesos en este dispositivo',
              accion: (accesos.value?.isNotEmpty ?? false) && user != null
                  ? TextButton(onPressed: () => _borrarHistorial(user.email), child: const Text('Borrar'))
                  : null,
              children: accesos.when(
                loading: () => [const LinearProgressIndicator(color: AppColors.primary)],
                error: (_, _) => [const ListTile(title: Text('No se pudo leer el historial local'))],
                data: (list) => list.isEmpty
                    ? [const ListTile(title: Text('Sin registros', style: TextStyle(color: AppColors.textMuted)))]
                    : [
                        for (final a in list)
                          ListTile(
                            dense: true,
                            leading: Icon(_iconoMetodo(a.metodo), color: AppColors.primary),
                            title: Text(a.metodo),
                            subtitle: Text(_fecha(a.fecha),
                                style: const TextStyle(color: AppColors.textMuted)),
                          ),
                      ],
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => ref.read(authControllerProvider.notifier).logout(),
              icon: const Icon(Icons.logout, color: AppColors.error),
              label: const Text('Cerrar sesión', style: TextStyle(color: AppColors.error)),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _iconoMetodo(String m) => switch (m) {
        MetodoAcceso.biometria => Icons.fingerprint,
        MetodoAcceso.passwordOtp => Icons.verified_user_outlined,
        MetodoAcceso.registro => Icons.person_add_alt_outlined,
        _ => Icons.key_outlined,
      };

  static String _fecha(DateTime d, {bool conHora = true}) {
    String two(int n) => n.toString().padLeft(2, '0');
    final f = '${two(d.day)}/${two(d.month)}/${d.year}';
    return conHora ? '$f  ${two(d.hour)}:${two(d.minute)}' : f;
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.nombre, required this.cargando, this.onTap});

  final String? url;
  final String nombre;
  final bool cargando;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final inicial = nombre.isNotEmpty ? nombre[0].toUpperCase() : '?';
    return Semantics(
      button: true,
      label: 'Foto de perfil. Toca para cambiarla',
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircleAvatar(
              radius: 56,
              backgroundColor: AppColors.surfaceHigh,
              foregroundImage: url != null ? NetworkImage(url!) : null,
              onForegroundImageError: url != null ? (_, _) {} : null,
              child: Text(inicial,
                  style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: AppColors.primary)),
            ),
            if (cargando)
              const SizedBox(
                width: 112,
                height: 112,
                child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3),
              ),
          ],
        ),
      ),
    );
  }
}

class _Seccion extends StatelessWidget {
  const _Seccion({required this.titulo, required this.children, this.accion});

  final String titulo;
  final List<Widget> children;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(titulo, style: const TextStyle(color: AppColors.textMuted))),
            ?accion,
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato(this.icon, this.label, this.value);

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textMuted),
      title: Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
      subtitle: Text(value, style: const TextStyle(color: Colors.white, fontSize: 15)),
    );
  }
}
