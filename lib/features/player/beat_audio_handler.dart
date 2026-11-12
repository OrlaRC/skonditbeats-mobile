import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../catalog/domain/beat.dart';

/// Conecta el reproductor con el sistema: mantiene la música en segundo plano
/// y atiende la notificación, la pantalla de bloqueo y los audífonos Bluetooth.
class BeatAudioHandler extends BaseAudioHandler with SeekHandler {
  BeatAudioHandler() {
    player.playbackEventStream.listen(
      (_) => _publishState(),
      onError: (Object _, StackTrace _) {}, // El controlador muestra el error.
    );
  }

  final AudioPlayer player = AudioPlayer();

  /// Los asigna el controlador, que es quien conoce la lista de reproducción.
  Future<void> Function(int delta)? onSkip;
  void Function()? onStopped;

  /// El controlador avisa si la lista cambió; los botones se muestran siempre.
  set canSkip(bool value) => _publishState();

  /// Carga el beat, lo publica en el sistema y empieza a sonar.
  Future<void> playBeat(Beat beat) async {
    final item = MediaItem(
      id: beat.id,
      title: beat.nombre,
      artist: 'SkonditBeats',
      album: '${beat.genero} · ${beat.bpm} BPM',
      artUri: beat.imagenUrl == null ? null : Uri.tryParse(beat.imagenUrl!),
    );
    mediaItem.add(item);
    final duration = await player.setUrl(beat.audioUrl!);
    mediaItem.add(item.copyWith(duration: duration));
    unawaited(player.play()); // play() termina hasta que la pista se pausa o acaba.
  }

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> skipToNext() async => onSkip?.call(1);

  @override
  Future<void> skipToPrevious() async => onSkip?.call(-1);

  @override
  Future<void> stop() async {
    await player.stop();
    onStopped?.call();
  }

  // Si el usuario quita la app de recientes, la música y el aviso se cierran.
  @override
  Future<void> onTaskRemoved() => stop();

  /// "X" de la notificación: detiene la música y quita el reproductor.
  static const _cerrar = MediaControl(
    androidIcon: 'drawable/ic_cerrar',
    label: 'Cerrar',
    action: MediaAction.stop,
  );

  /// Anterior y siguiente siempre visibles (en la notificación, la pantalla de
  /// bloqueo y los audífonos); con un solo beat en la lista no hacen nada.
  void _publishState() {
    final playing = player.playing;
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
        _cerrar,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.skipToPrevious,
        MediaAction.skipToNext,
        MediaAction.stop,
      },
      // Vista compacta: anterior, play/pausa y siguiente; la X se ve al expandir.
      androidCompactActionIndices: const [0, 1, 2],
      processingState: switch (player.processingState) {
        ProcessingState.idle => AudioProcessingState.idle,
        ProcessingState.loading => AudioProcessingState.loading,
        ProcessingState.buffering => AudioProcessingState.buffering,
        ProcessingState.ready => AudioProcessingState.ready,
        ProcessingState.completed => AudioProcessingState.completed,
      },
      playing: playing,
      updatePosition: player.position,
      bufferedPosition: player.bufferedPosition,
      speed: player.speed,
    ));
  }
}

/// Se crea en `main` con `AudioService.init` y se inyecta en el ProviderScope.
final audioHandlerProvider = Provider<BeatAudioHandler>(
  (ref) => throw UnimplementedError('audioHandlerProvider se inyecta en main()'),
);
