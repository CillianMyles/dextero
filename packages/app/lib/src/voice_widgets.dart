import 'package:flutter/widgets.dart';
import 'package:shad/shad.dart';

import 'dextero_design.dart';
import 'voice_controller.dart';

/// One glanceable line that says what Dextero is doing right now.
class AgentPresence extends StatelessWidget {
  const AgentPresence({required this.voice, super.key});

  final VoiceController voice;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;
    final presence = voice.presence;
    final tool = _toolLabel(voice.activeToolName);
    final (icon, color, label, detail) = switch (presence) {
      Presence.offline => (
        LucideIcons.cloudOff,
        scheme.mutedForeground,
        'Offline',
        null,
      ),
      Presence.ready => (
        LucideIcons.sparkles,
        scheme.mutedForeground,
        'Ready',
        voice.available ? 'Tap the microphone to talk.' : null,
      ),
      Presence.listening => (
        LucideIcons.mic,
        scheme.destructive,
        'Listening',
        'Microphone on · ${formatElapsed(voice.elapsed)}',
      ),
      Presence.transcribing => (
        LucideIcons.audioLines,
        DexteroDesign.warning(theme.brightness),
        'Transcribing',
        'Microphone off',
      ),
      Presence.thinking => (
        LucideIcons.brain,
        scheme.primary,
        'Thinking',
        null,
      ),
      Presence.acting => (
        LucideIcons.wrench,
        scheme.primary,
        'Working',
        tool == null ? null : 'Using $tool',
      ),
      Presence.awaitingApproval => (
        LucideIcons.shieldAlert,
        DexteroDesign.warning(theme.brightness),
        'Waiting for your approval',
        tool,
      ),
      Presence.speaking => (
        LucideIcons.volume2,
        DexteroDesign.success(theme.brightness),
        'Speaking',
        voice.speechReady ? null : 'Preparing the spoken reply',
      ),
    };
    final level = presence == Presence.listening ? voice.level : 0.0;
    return Semantics(
      liveRegion: true,
      label: detail == null ? label : '$label. $detail',
      child: ExcludeSemantics(
        child: Container(
          key: const Key('agent-presence'),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.07),
            border: Border.all(color: color.withValues(alpha: 0.22)),
            borderRadius: theme.radius,
          ),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 36,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width: 26 + 10 * level,
                      height: 26 + 10 * level,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withValues(alpha: 0.16 + 0.3 * level),
                      ),
                    ),
                    Icon(icon, size: 15, color: color),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      key: const Key('agent-presence-label'),
                      style: theme.textTheme.small.copyWith(
                        color: scheme.foreground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (detail != null)
                      Text(
                        detail,
                        key: const Key('agent-presence-detail'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.small.copyWith(
                          color: scheme.mutedForeground,
                        ),
                      ),
                  ],
                ),
              ),
              if (presence == Presence.speaking)
                ShadButton.outline(
                  key: const Key('stop-speaking'),
                  size: ShadButtonSize.sm,
                  onPressed: voice.stopSpeaking,
                  leading: const Icon(LucideIcons.square, size: 13),
                  child: const Text('Stop'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String? _toolLabel(String? toolName) =>
      toolName?.replaceAll(RegExp(r'[._-]+'), ' ');
}

/// Replaces the composer while the microphone is open or the clip is being
/// transcribed, so recording is impossible to miss.
class RecordingBar extends StatelessWidget {
  const RecordingBar({required this.voice, super.key});

  final VoiceController voice;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final scheme = theme.colorScheme;
    final listening = voice.phase == VoicePhase.listening;
    final remaining = voice.maxRecording - voice.elapsed;
    return Container(
      key: const Key('recording-bar'),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.card,
        border: Border.all(
          color: listening
              ? scheme.destructive.withValues(alpha: 0.5)
              : scheme.border,
        ),
        borderRadius: theme.radius,
      ),
      child: Row(
        children: [
          if (listening) ...[
            Container(
              key: const Key('recording-indicator'),
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: scheme.destructive,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                remaining <= const Duration(seconds: 10)
                    ? 'Recording ${formatElapsed(voice.elapsed)} · '
                          '${remaining.inSeconds}s left'
                    : 'Recording ${formatElapsed(voice.elapsed)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.small.copyWith(
                  color: scheme.foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: _LevelMeter(level: voice.level)),
            const SizedBox(width: 8),
            ShadIconButton.ghost(
              key: const Key('cancel-voice'),
              semanticLabel: 'Discard recording',
              onPressed: voice.cancelListening,
              icon: const Icon(LucideIcons.x),
            ),
            const SizedBox(width: 4),
            ShadIconButton(
              key: const Key('finish-voice'),
              semanticLabel: 'Send voice message',
              onPressed: voice.finishListening,
              icon: const Icon(LucideIcons.arrowUp),
            ),
          ] else ...[
            const ShadSpinner(size: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Transcribing your message…',
                style: theme.textTheme.small.copyWith(
                  color: scheme.mutedForeground,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LevelMeter extends StatelessWidget {
  const _LevelMeter({required this.level});

  final double level;

  static const _weights = [0.45, 0.75, 1.0, 0.75, 0.45, 0.65, 0.9];
  static const _barExtent = 7.0;

  @override
  Widget build(BuildContext context) {
    final color = ShadTheme.of(context).colorScheme.destructive;
    return SizedBox(
      height: 22,
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            for (final weight in _weights.take(
              (constraints.maxWidth / _barExtent).floor(),
            ))
              AnimatedContainer(
                duration: const Duration(milliseconds: 90),
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                width: 4,
                height: 4 + 18 * (level * weight).clamp(0.0, 1.0),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String formatElapsed(Duration value) =>
    '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';
