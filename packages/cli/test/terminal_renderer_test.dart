import 'package:dextero_cli/dextero_cli.dart';
import 'package:dextero_server/dextero_client.dart';
import 'package:test/test.dart';

void main() {
  test('renders streamed output in a terminal frame', () {
    final status = HostStatus(
      name: 'Dextero',
      version: '0.0.1',
      startedAt: DateTime.utc(2026),
      persistence: 'memory',
      databaseRequired: false,
      streamingAvailable: true,
    );
    final output = TaskEvent(
      taskId: 'task-1',
      sequence: 2,
      kind: TaskEventKind.output,
      message: 'Finished the work',
      timestamp: DateTime.utc(2026),
      terminal: false,
    );

    final frame = const TerminalRenderer().frame(
      status: status,
      prompt: 'Inspect the repo',
      events: [output],
    );

    expect(frame, contains('DEXTERO'));
    expect(frame, contains('Inspect the repo'));
    expect(frame, contains('Finished the work'));
  });
}
