import 'dart:async';

import 'package:dextero_server/dextero_client.dart';
import 'package:flutter/foundation.dart';

import 'dextero_controller.dart';
import 'voice_audio.dart';

/// Client-local voice phases layered over the host agent's activity.
enum VoicePhase { idle, listening, transcribing, speaking }

/// What the presence indicator shows; one value per visible state.
enum Presence {
  offline,
  ready,
  listening,
  transcribing,
  thinking,
  acting,
  awaitingApproval,
  speaking,
}

/// Owns push-to-talk capture and spoken replies for one conversation.
///
/// The microphone is open only between [startListening] and
/// [finishListening] or [cancelListening]. Replies are spoken only for turns
/// this device started by voice.
final class VoiceController extends ChangeNotifier {
  VoiceController({
    required DexteroController chat,
    required VoiceRecorder recorder,
    required SpeechPlayer player,
    this.maxRecording = const Duration(seconds: 60),
  }) : _chat = chat,
       _recorder = recorder,
       _player = player {
    _chat.addListener(_onChatChanged);
  }

  static const _tick = Duration(milliseconds: 200);

  final DexteroController _chat;
  final VoiceRecorder _recorder;
  final SpeechPlayer _player;
  final Duration maxRecording;
  VoicePhase _phase = VoicePhase.idle;
  double _level = 0;
  Duration _elapsed = Duration.zero;
  Timer? _ticker;
  bool _starting = false;
  bool _speechReady = false;
  String? _replyRunId;
  String? _error;
  bool _disposed = false;

  VoicePhase get phase => _phase;
  double get level => _level;
  Duration get elapsed => _elapsed;
  String? get error => _error;

  /// Whether reply audio is playing, as opposed to being generated.
  bool get speechReady => _speechReady;

  bool get available => _chat.hostStatus?.voiceInputAvailable ?? false;

  bool get canStartListening =>
      available &&
      !_starting &&
      (_phase == VoicePhase.idle || _phase == VoicePhase.speaking) &&
      _chat.canSubmit;

  Presence get presence {
    if (_chat.hostStatus == null) return Presence.offline;
    switch (_phase) {
      case VoicePhase.listening:
        return Presence.listening;
      case VoicePhase.transcribing:
        return Presence.transcribing;
      case VoicePhase.speaking:
        return Presence.speaking;
      case VoicePhase.idle:
        break;
    }
    if (_chat.pendingApproval != null) return Presence.awaitingApproval;
    if (!_chat.busy) return Presence.ready;
    return agentActivityOf(_chat.entries).activity == AgentActivity.acting
        ? Presence.acting
        : Presence.thinking;
  }

  /// The tool currently in use or awaiting approval, when known.
  String? get activeToolName =>
      _chat.pendingApproval?.toolName ??
      (_chat.busy ? agentActivityOf(_chat.entries).toolName : null);

  Future<void> startListening() async {
    if (!canStartListening) return;
    _starting = true;
    _error = null;
    _replyRunId = null;
    _notify();
    if (_phase == VoicePhase.speaking) await stopSpeaking();
    var started = false;
    try {
      started = await _recorder.start(
        onLevel: (level) {
          if (_phase != VoicePhase.listening) return;
          _level = level;
          _notify();
        },
      );
      if (!started) {
        _error =
            'Microphone access was denied. Allow it in system settings to '
            'talk to Dextero.';
      }
    } on TimeoutException catch (error) {
      _error = 'The microphone did not start: ${error.message}';
    } on Object catch (error) {
      _error = 'The microphone could not start: $error';
    } finally {
      _starting = false;
    }
    if (!started || _disposed) {
      _notify();
      return;
    }
    _phase = VoicePhase.listening;
    _level = 0;
    _elapsed = Duration.zero;
    _ticker = Timer.periodic(_tick, (_) {
      _elapsed += _tick;
      if (_elapsed >= maxRecording) {
        unawaited(finishListening());
      } else {
        _notify();
      }
    });
    _notify();
  }

  /// Stops recording and sends the clip to the host for transcription.
  Future<void> finishListening() async {
    if (_phase != VoicePhase.listening) return;
    _stopTicker();
    _phase = VoicePhase.transcribing;
    _level = 0;
    _notify();
    RecordedClip? clip;
    try {
      clip = await _recorder.stop();
    } on Object catch (error) {
      _error = 'Recording failed: $error';
    }
    if (clip == null) {
      _error ??= 'Nothing was recorded.';
      _phase = VoicePhase.idle;
      _notify();
      return;
    }
    final runId = await _chat.submitVoice(clip.bytes, mimeType: clip.mimeType);
    if (runId == null && _chat.error == null) {
      _error = 'The recording was not sent because Dextero is busy.';
    }
    _phase = VoicePhase.idle;
    _replyRunId = runId;
    _notify();
    _onChatChanged();
  }

  /// Stops recording and discards the audio without sending it.
  Future<void> cancelListening() async {
    if (_phase != VoicePhase.listening) return;
    _stopTicker();
    _phase = VoicePhase.idle;
    _level = 0;
    _notify();
    await _recorder.cancel();
  }

  Future<void> stopSpeaking() async {
    if (_phase != VoicePhase.speaking) return;
    _phase = VoicePhase.idle;
    _speechReady = false;
    _notify();
    await _player.stop();
  }

  void _onChatChanged() {
    final runId = _replyRunId;
    if (runId == null) {
      _notify();
      return;
    }
    final entries = _chat.entries.where((entry) => entry.runId == runId);
    final terminal = entries.where(isTerminalRunEntry).firstOrNull;
    if (terminal == null) {
      _notify();
      return;
    }
    _replyRunId = null;
    final reply = entries
        .where((entry) => entry.kind == ChatEntryKind.assistantMessage)
        .lastOrNull;
    if (terminal.status != ChatEntryStatus.completed ||
        reply == null ||
        !(_chat.hostStatus?.voiceOutputAvailable ?? false)) {
      _notify();
      return;
    }
    unawaited(_speak(reply.entryId));
  }

  Future<void> _speak(String entryId) async {
    _phase = VoicePhase.speaking;
    _speechReady = false;
    _notify();
    try {
      final reply = await _chat.speakReply(entryId);
      if (reply == null || _phase != VoicePhase.speaking || _disposed) return;
      _speechReady = true;
      _notify();
      await _player.play(
        reply.audio.buffer.asUint8List(
          reply.audio.offsetInBytes,
          reply.audio.lengthInBytes,
        ),
        mimeType: reply.mimeType,
      );
    } on Object catch (error) {
      _error = 'The reply could not be played: $error';
    } finally {
      if (_phase == VoicePhase.speaking) {
        _phase = VoicePhase.idle;
        _speechReady = false;
        _notify();
      }
    }
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopTicker();
    _chat.removeListener(_onChatChanged);
    unawaited(_recorder.dispose());
    unawaited(_player.dispose());
    super.dispose();
  }
}
