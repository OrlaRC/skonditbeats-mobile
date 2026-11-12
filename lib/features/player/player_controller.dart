import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../auth/presentation/auth_controller.dart';
import '../catalog/domain/beat.dart';
import 'beat_audio_handler.dart';

class NowPlaying {
  const NowPlaying({this.beat, this.playing = false, this.loading = false, this.error});

  final Beat? beat;
  final bool playing;
  final bool loading;
  final String? error;

  bool isBeat(String id) => beat?.id == id;
}

/// El beat que sigue en la lista, dando la vuelta al llegar a un extremo.
/// Devuelve null si no hay otro beat al cual saltar.
Beat? beatInQueue(List<Beat> queue, String currentId, int delta) {
  if (queue.length < 2) return null;
  final i = queue.indexWhere((b) => b.id == currentId);
  if (i < 0) return null;
  return queue[(i + delta) % queue.length];
}

/// Reproductor único de la app (vista previa de los beats).
///
/// Usa el canal multimedia del teléfono: los botones físicos de volumen lo
/// controlan, se pausa con una llamada (foco de audio) y al desconectar los
/// audífonos (handleInterruptions de just_audio + audio_session). Sigue sonando
/// en segundo plano y se controla desde la pantalla de bloqueo ([BeatAudioHandler]).
class PlayerController extends Notifier<NowPlaying> {
  late final BeatAudioHandler _handler;
  StreamSubscription<PlayerState>? _sub;

  /// Lista desde la que se reprodujo el beat, para "anterior" y "siguiente".
  List<Beat> _queue = const [];

  /// Identifica la última carga: si el usuario salta rápido, se ignora la anterior.
  int _loadId = 0;

  AudioPlayer get player => _handler.player;

  @override
  NowPlaying build() {
    _handler = ref.read(audioHandlerProvider);
    _handler
      ..onSkip = _skip
      ..onStopped = _onStopped;
    _configureSession();

    _sub = player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) {
        player.pause();
        player.seek(Duration.zero);
      }
      state = NowPlaying(
        beat: state.beat,
        playing: s.playing && s.processingState != ProcessingState.completed,
        loading: s.processingState == ProcessingState.loading ||
            s.processingState == ProcessingState.buffering,
      );
    });

    // Al cerrar sesión se detiene la música.
    ref.listen(authControllerProvider, (_, next) {
      if (!next.isAuthenticated) stop();
    });

    ref.onDispose(() {
      _sub?.cancel();
      _handler
        ..onSkip = null
        ..onStopped = null;
    });
    return const NowPlaying();
  }

  Future<void> _configureSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  }

  /// Reproduce el beat, o pausa/reanuda si ya es el actual.
  ///
  /// [queue] es la lista visible en pantalla; sin ella se conserva la actual
  /// si el beat pertenece a esa lista.
  Future<void> toggle(Beat beat, {List<Beat>? queue}) async {
    if (!beat.tieneAudio) {
      state = NowPlaying(beat: state.beat, error: 'Este beat no tiene vista previa');
      return;
    }
    if (queue != null) {
      _setQueue(queue);
    } else if (!_queue.any((b) => b.id == beat.id)) {
      _setQueue([beat]);
    }
    if (state.isBeat(beat.id)) {
      player.playing ? await _handler.pause() : await _handler.play();
      return;
    }
    await _load(beat);
  }

  void _setQueue(List<Beat> queue) {
    _queue = queue.where((b) => b.tieneAudio).toList();
    _handler.canSkip = _queue.length > 1;
  }

  Future<void> _load(Beat beat) async {
    final id = ++_loadId;
    state = NowPlaying(beat: beat, loading: true);
    try {
      await _handler.playBeat(beat);
    } catch (_) {
      if (id == _loadId) {
        state = NowPlaying(beat: beat, error: 'No se pudo reproducir "${beat.nombre}"');
      }
    }
  }

  Future<void> _skip(int delta) async {
    final current = state.beat;
    if (current == null) return;
    final target = beatInQueue(_queue, current.id, delta);
    if (target != null) await _load(target);
  }

  Future<void> stop() => _handler.stop();

  void _onStopped() {
    _loadId++;
    _queue = const [];
    _handler.canSkip = false;
    state = const NowPlaying();
  }
}

final playerProvider = NotifierProvider<PlayerController, NowPlaying>(PlayerController.new);

final playerPositionProvider = StreamProvider.autoDispose<(Duration, Duration?)>((ref) {
  final player = ref.watch(playerProvider.notifier).player;
  return player.positionStream.map((p) => (p, player.duration));
});
