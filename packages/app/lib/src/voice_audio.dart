import 'dart:math';
import 'dart:typed_data';

/// A finished push-to-talk clip ready to send to the host.
final class RecordedClip {
  const RecordedClip({
    required this.bytes,
    required this.mimeType,
    required this.duration,
  });

  final Uint8List bytes;
  final String mimeType;
  final Duration duration;
}

/// Captures microphone audio only between [start] and [stop] or [cancel].
abstract interface class VoiceRecorder {
  /// Starts capture and reports input levels from 0 to 1. Returns false when
  /// microphone access is denied.
  Future<bool> start({required void Function(double level) onLevel});

  /// Ends capture and returns the clip, or null when nothing was captured.
  Future<RecordedClip?> stop();

  /// Ends capture and discards the audio.
  Future<void> cancel();

  Future<void> dispose();
}

abstract interface class SpeechPlayer {
  /// Plays [bytes]; completes when playback ends or [stop] is called.
  Future<void> play(Uint8List bytes, {required String mimeType});

  Future<void> stop();

  Future<void> dispose();
}

/// The format sent to the host: small enough for a minute of speech and what
/// whisper.cpp expects.
const voiceSampleRate = 16000;

/// Wraps little-endian 16-bit PCM samples in a WAV container.
Uint8List encodeWav(
  Uint8List pcm, {
  int sampleRate = voiceSampleRate,
  int channels = 1,
}) {
  final header = ByteData(44);
  void ascii(int offset, String value) {
    for (var index = 0; index < value.length; index++) {
      header.setUint8(offset + index, value.codeUnitAt(index));
    }
  }

  ascii(0, 'RIFF');
  header.setUint32(4, 36 + pcm.length, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  header
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, channels, Endian.little)
    ..setUint32(24, sampleRate, Endian.little)
    ..setUint32(28, sampleRate * channels * 2, Endian.little)
    ..setUint16(32, channels * 2, Endian.little)
    ..setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  header.setUint32(40, pcm.length, Endian.little);
  return (BytesBuilder(copy: false)
        ..add(header.buffer.asUint8List())
        ..add(pcm))
      .takeBytes();
}

/// Downmixes interleaved 16-bit PCM to mono and linearly resamples it to
/// [voiceSampleRate], whatever rate the platform actually captured.
Uint8List toVoicePcm(
  Uint8List pcm, {
  required int sampleRate,
  required int channels,
}) {
  final input = ByteData.sublistView(pcm);
  final frames = pcm.length ~/ (2 * channels);
  double frame(int index) {
    var sum = 0;
    for (var channel = 0; channel < channels; channel++) {
      sum += input.getInt16((index * channels + channel) * 2, Endian.little);
    }
    return sum / channels;
  }

  if (sampleRate == voiceSampleRate && channels == 1) {
    return Uint8List.sublistView(pcm, 0, frames * 2);
  }
  final outputFrames = frames * voiceSampleRate ~/ sampleRate;
  final output = ByteData(outputFrames * 2);
  for (var index = 0; index < outputFrames; index++) {
    final position = index * sampleRate / voiceSampleRate;
    final left = position.floor();
    final right = min(left + 1, frames - 1);
    final weight = position - left;
    final value = frame(left) * (1 - weight) + frame(right) * weight;
    output.setInt16(
      index * 2,
      value.round().clamp(-32768, 32767),
      Endian.little,
    );
  }
  return output.buffer.asUint8List();
}

/// A perceptual 0–1 input level for one chunk of 16-bit PCM.
double pcm16Level(Uint8List chunk) {
  final samples = chunk.length ~/ 2;
  if (samples == 0) return 0;
  final data = ByteData.sublistView(chunk);
  var sumOfSquares = 0.0;
  for (var index = 0; index < samples; index++) {
    final sample = data.getInt16(index * 2, Endian.little) / 32768;
    sumOfSquares += sample * sample;
  }
  return min(1, sqrt(sqrt(sumOfSquares / samples)) * 1.8);
}
