import 'dart:async';

import 'package:serverpod/serverpod.dart';

import '../generated/protocol.dart';

/// The first typed control-plane slice exposed to trusted controllers.
final class ControlEndpoint extends Endpoint {
  static final DateTime _startedAt = DateTime.now().toUtc();
  static int _taskSequence = 0;

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

  /// Streams a deterministic task lifecycle over Serverpod's method stream.
  ///
  /// This proves the generated client and WebSocket event path without giving
  /// the remote surface authority to run arbitrary tools yet.
  Stream<TaskEvent> runDemo(Session session, int steps) async* {
    if (steps < 1 || steps > 20) {
      throw ArgumentError.value(steps, 'steps', 'must be between 1 and 20');
    }

    final taskId = 'demo-${++_taskSequence}';
    var sequence = 0;
    yield _event(
      taskId: taskId,
      sequence: sequence++,
      kind: TaskEventKind.queued,
      message: 'Demo task queued',
    );

    for (var step = 1; step <= steps; step++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      yield _event(
        taskId: taskId,
        sequence: sequence++,
        kind: TaskEventKind.running,
        message: 'Completed step $step of $steps',
      );
    }

    yield _event(
      taskId: taskId,
      sequence: sequence,
      kind: TaskEventKind.completed,
      message: 'Demo task completed',
      terminal: true,
    );
  }

  TaskEvent _event({
    required String taskId,
    required int sequence,
    required TaskEventKind kind,
    required String message,
    bool terminal = false,
  }) => TaskEvent(
    taskId: taskId,
    sequence: sequence,
    kind: kind,
    message: message,
    timestamp: DateTime.now().toUtc(),
    terminal: terminal,
  );
}
