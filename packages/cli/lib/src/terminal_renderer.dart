import 'package:dextero_server/dextero_client.dart';

final class TerminalRenderer {
  const TerminalRenderer();

  String frame({
    required HostStatus status,
    required List<ChatEntry> entries,
    String? notice,
  }) {
    final buffer = StringBuffer()
      ..writeln(
        '\x1b[2J\x1b[H\x1b[1;36mDEXTERO\x1b[0m  '
        '${_terminalSafe(status.name)} ${_terminalSafe(status.version)}',
      )
      ..writeln('\x1b[2m${_rule()}\x1b[0m')
      ..writeln('\x1b[2m${_terminalSafe(status.retentionNotice)}\x1b[0m')
      ..writeln();

    for (final entry in entries) {
      buffer.writeln(entryLine(entry));
    }
    if (entries.isEmpty) {
      buffer.writeln('\x1b[2mNo messages yet. Type a message below.\x1b[0m');
    }
    if (notice != null) {
      buffer.writeln('\n\x1b[2m${_terminalSafe(notice)}\x1b[0m');
    }
    return buffer.toString();
  }

  String entryLine(ChatEntry entry) {
    final (symbol, color, label) = switch (entry.kind) {
      ChatEntryKind.userMessage => ('YOU', '35', 'you'),
      ChatEntryKind.assistantMessage => ('DEX', '36', 'dextero'),
      ChatEntryKind.toolCall => ('›', '34', entry.toolName ?? 'tool'),
      ChatEntryKind.toolResult => (
        entry.status == ChatEntryStatus.failed ? '×' : '✓',
        entry.status == ChatEntryStatus.failed ? '31' : '32',
        entry.toolName ?? 'tool',
      ),
      ChatEntryKind.lifecycle => ('·', '33', entry.status.name),
      ChatEntryKind.error => ('×', '31', 'error'),
    };
    final safeLabel = _terminalSafe(label);
    final content = _terminalSafe(entry.content).replaceAll('\n', '\n    ');
    return '\x1b[${color}m$symbol\x1b[0m '
        '\x1b[2m${safeLabel.padRight(12)}\x1b[0m $content';
  }

  String plainEntryLine(ChatEntry entry) {
    final label = switch (entry.kind) {
      ChatEntryKind.userMessage => 'you',
      ChatEntryKind.assistantMessage => 'dextero',
      ChatEntryKind.toolCall ||
      ChatEntryKind.toolResult => entry.toolName ?? entry.kind.name,
      ChatEntryKind.lifecycle => entry.status.name,
      ChatEntryKind.error => 'error',
    };
    return '[${_terminalSafe(label)}] ${_terminalSafe(entry.content)}';
  }

  String _rule() => '─' * 72;

  String _terminalSafe(String value) => value
      .replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '')
      .replaceAll(
        RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F]'),
        '',
      );
}
