import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:record/record.dart';

import 'voice_audio.dart';

/// Streams microphone PCM through the `record` plugin and packages it as
/// 16 kHz mono WAV. Plugin objects are created on first use.
final class PluginVoiceRecorder implements VoiceRecorder {
  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _subscription;
  Completer<void>? _streamDone;
  final _pcm = BytesBuilder(copy: false);
  var _sampleRate = voiceSampleRate;
  var _channels = 1;

  @override
  Future<bool> start({required void Function(double level) onLevel}) async {
    final recorder = _recorder ??= AudioRecorder();
    if (!await recorder.hasPermission()) return false;
    // Fail clearly when the platform reports no microphone at all.
    if ((await recorder.listInputDevices()).isEmpty) {
      throw StateError('No microphone input is available.');
    }
    _pcm.clear();
    _sampleRate = voiceSampleRate;
    _channels = 1;
    await recorder.setOnConfigChanged((config) {
      _sampleRate = config.sampleRate;
      _channels = config.numChannels;
    });
    final stream = await recorder
        .startStream(
          const RecordConfig(
            encoder: AudioEncoder.pcm16bits,
            sampleRate: voiceSampleRate,
            numChannels: 1,
            echoCancel: true,
            noiseSuppress: true,
          ),
        )
        .timeout(
          const Duration(seconds: 5),
          onTimeout: () async {
            await recorder.cancel();
            throw TimeoutException('No microphone input is available.');
          },
        );
    final done = _streamDone = Completer<void>();
    _subscription = stream.listen(
      (chunk) {
        _pcm.add(chunk);
        onLevel(pcm16Level(chunk));
      },
      onDone: done.complete,
      onError: (Object _) {
        if (!done.isCompleted) done.complete();
      },
    );
    return true;
  }

  @override
  Future<RecordedClip?> stop() async {
    final recorder = _recorder;
    if (recorder == null) return null;
    await recorder.stop();
    await _streamDone?.future.timeout(
      const Duration(seconds: 1),
      onTimeout: () {},
    );
    await _subscription?.cancel();
    _subscription = null;
    final pcm = toVoicePcm(
      _pcm.takeBytes(),
      sampleRate: _sampleRate,
      channels: _channels,
    );
    if (pcm.isEmpty) return null;
    return RecordedClip(
      bytes: encodeWav(pcm),
      mimeType: 'audio/wav',
      duration: Duration(
        microseconds: pcm.length ~/ 2 * 1000000 ~/ voiceSampleRate,
      ),
    );
  }

  @override
  Future<void> cancel() async {
    await _recorder?.cancel();
    await _subscription?.cancel();
    _subscription = null;
    _pcm.clear();
  }

  @override
  Future<void> dispose() async {
    await cancel();
    await _recorder?.dispose();
  }
}

/// Plays spoken replies through the `audioplayers` plugin. Native platforms
/// play from a private temporary file that is deleted when playback ends.
final class PluginSpeechPlayer implements SpeechPlayer {
  AudioPlayer? _player;
  StreamSubscription<void>? _completions;
  Completer<void>? _playback;
  Directory? _directory;

  @override
  Future<void> play(Uint8List bytes, {required String mimeType}) async {
    await stop();
    final player = _player ??= AudioPlayer();
    _completions ??= player.onPlayerComplete.listen((_) => _finish());
    final playback = _playback = Completer<void>();
    if (kIsWeb) {
      await player.play(BytesSource(bytes, mimeType: mimeType));
    } else {
      final directory = _directory = await Directory.systemTemp.createTemp(
        'dextero-reply-',
      );
      final file = File('${directory.path}${Platform.pathSeparator}reply.wav');
      await file.writeAsBytes(bytes, flush: true);
      await player.play(DeviceFileSource(file.path, mimeType: mimeType));
    }
    return playback.future;
  }

  @override
  Future<void> stop() async {
    await _player?.stop();
    _finish();
  }

  void _finish() {
    final playback = _playback;
    _playback = null;
    if (playback != null && !playback.isCompleted) playback.complete();
    final directory = _directory;
    _directory = null;
    if (directory != null) {
      unawaited(
        directory.delete(recursive: true).then((_) {}, onError: (Object _) {}),
      );
    }
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _completions?.cancel();
    await _player?.dispose();
  }
}
