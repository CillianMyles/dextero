import 'package:dextero_server/dextero_client.dart';

final class TerminalRenderer {
  const TerminalRenderer();

  String frame({
    required HostStatus status,
    required String prompt,
    required List<TaskEvent> events,
  }) {
    final buffer = StringBuffer()
      ..writeln(
        '\x1b[2J\x1b[H\x1b[1;36mDEXTERO\x1b[0m  ${status.name} ${status.version}',
      )
      ..writeln('\x1b[2m${_rule()}\x1b[0m')
      ..writeln('\x1b[1mTask\x1b[0m  $prompt')
      ..writeln();

    for (final event in events) {
      buffer.writeln(eventLine(event));
    }
    if (events.isEmpty) buffer.writeln('\x1b[2mWaiting for the server…\x1b[0m');
    return buffer.toString();
  }

  String eventLine(TaskEvent event) {
    final (symbol, color) = switch (event.kind) {
      TaskEventKind.queued => ('○', '33'),
      TaskEventKind.running => ('◌', '34'),
      TaskEventKind.output => ('›', '36'),
      TaskEventKind.completed => ('✓', '32'),
      TaskEventKind.failed => ('×', '31'),
    };
    final message = event.message.replaceAll('\n', '\n    ');
    return '\x1b[${color}m$symbol\x1b[0m '
        '\x1b[2m${event.kind.name.padRight(9)}\x1b[0m $message';
  }

  String plainEventLine(TaskEvent event) =>
      '[${event.kind.name}] ${event.message}';

  String _rule() => '─' * 72;
}
