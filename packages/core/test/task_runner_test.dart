import 'dart:async';
import 'dart:io';

import 'package:dextero_core/dextero_core.dart';
import 'package:test/test.dart';

void main() {
  test('rejects an empty task before launching Codex', () async {
    final runner = CodexTaskRunner(workspace: '.');

    await expectLater(runner.run('   '), emitsError(isA<ArgumentError>()));
  });

  test('gates every file edit through the exported task runner', () async {
    final workspace = await Directory.systemTemp.createTemp(
      'dextero-task-runner-',
    );
    addTearDown(() => workspace.delete(recursive: true));
    final file = File('${workspace.path}/README.md');
    await file.writeAsString('old heading\n');
    final transport = _EditTransport();
    final requested = Completer<ToolApprovalRequest>();
    final decision = Completer<bool>();
    final runner = CodexTaskRunner(
      workspace: workspace.path,
      transportFactory: () async => transport,
      onApprovalRequest: (request) {
        requested.complete(request);
        return decision.future;
      },
    );

    final eventsFuture = runner.run('Update the heading').toList();
    final request = await requested.future;

    expect(request.toolName, 'edit_file');
    expect(request.summary.text, contains('-old heading'));
    expect(request.summary.text, contains('+new heading'));
    expect(await file.readAsString(), 'old heading\n');

    decision.complete(true);
    final events = await eventsFuture;

    expect(await file.readAsString(), 'new heading\n');
    expect(events.last.kind, CoreTaskEventKind.completed);
    expect(events.last.terminal, isTrue);
  });
}

final class _EditTransport implements CodexAppServerTransport {
  final _messages = StreamController<JsonMap>();

  @override
  Stream<JsonMap> get messages => _messages.stream;

  @override
  Future<void> send(JsonMap message) async {
    switch (message['method']) {
      case 'initialize':
        _messages.add({'id': 0, 'result': <String, Object?>{}});
      case 'thread/start':
        _messages.add({
          'id': 1,
          'result': {
            'thread': {'id': 'thread-1'},
          },
        });
      case 'turn/start':
        _messages.add({
          'id': 2,
          'result': {
            'turn': {'id': 'turn-1'},
          },
        });
        _messages.add({
          'id': 'tool-request-1',
          'method': 'item/tool/call',
          'params': {
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'callId': 'call-edit-1',
            'tool': 'edit_file',
            'arguments': {
              'path': 'README.md',
              'oldText': 'old heading',
              'newText': 'new heading',
            },
          },
        });
      case null:
        if (message['id'] != 'tool-request-1') return;
        _messages.add({
          'method': 'item/completed',
          'params': {
            'item': {'type': 'agentMessage', 'text': 'Updated the heading.'},
          },
        });
        _messages.add({
          'method': 'turn/completed',
          'params': {
            'turn': {'status': 'completed'},
          },
        });
    }
  }

  @override
  Future<void> close() async => _messages.close();
}
