import 'dart:async';

import 'package:dextero_core/dextero_core.dart';
import 'package:serverpod/serverpod.dart';

import '../generated/protocol.dart';
import 'task_runtime.dart';

/// The first typed control-plane slice exposed to trusted controllers.
final class ControlEndpoint extends Endpoint {
  static final DateTime _startedAt = DateTime.now().toUtc();

  @override
  bool get requireLogin => true;

  /// Describes the local host and its intentionally volatile MVP storage.
  Future<HostStatus> status(Session session) async => HostStatus(
    name: 'Dextero',
    version: '0.0.1',
    startedAt: _startedAt,
    persistence: 'memory',
    databaseRequired: false,
    streamingAvailable: true,
  );

  /// Starts work in the local core and streams its lifecycle and result.
  Stream<TaskEvent> runTask(Session session, String prompt) async* {
    final normalizedPrompt = prompt.trim();
    if (normalizedPrompt.isEmpty || normalizedPrompt.length > 32000) {
      throw ArgumentError.value(
        prompt,
        'prompt',
        'must contain between 1 and 32000 characters',
      );
    }

    await for (final event in TaskRuntime.runner.run(normalizedPrompt)) {
      yield _toProtocolEvent(event);
    }
  }

  TaskEvent _toProtocolEvent(CoreTaskEvent event) => TaskEvent(
    taskId: event.taskId,
    sequence: event.sequence,
    kind: TaskEventKind.values.byName(event.kind.name),
    message: event.message,
    timestamp: event.timestamp,
    terminal: event.terminal,
  );
}
