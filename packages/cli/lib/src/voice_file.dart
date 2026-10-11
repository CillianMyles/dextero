import 'dart:io';
import 'dart:typed_data';

/// A recorded clip read from disk for a one-shot voice turn.
final class VoiceFile {
  const VoiceFile({required this.bytes, required this.mimeType});

  final Uint8List bytes;
  final String mimeType;

  static Future<VoiceFile> read(String path) async {
    final mimeType = voiceMimeTypeForPath(path);
    if (mimeType == null) {
      throw ArgumentError.value(
        path,
        'path',
        'must be a .wav, .mp3, or .flac recording',
      );
    }
    return VoiceFile(bytes: await File(path).readAsBytes(), mimeType: mimeType);
  }
}

String? voiceMimeTypeForPath(String path) =>
    switch (path.toLowerCase().split('.').last) {
      'wav' || 'wave' => 'audio/wav',
      'mp3' => 'audio/mpeg',
      'flac' => 'audio/flac',
      _ => null,
    };
