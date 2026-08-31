import 'package:dextero_core/dextero_core.dart';
import 'package:dextero_server/src/auth/dextero_token_authenticator.dart';
import 'package:dextero_server/src/control/task_runtime.dart';
import 'package:dextero_server/src/generated/protocol.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

void main() {
  TaskRuntime.runner = _FakeTaskRunner();

  withServerpod('Control endpoint', (sessionBuilder, endpoints) {
    final authenticatedSession = sessionBuilder.copyWith(
      authentication: AuthenticationOverride.authenticationInfo(
        'test-controller',
        const {},
      ),
    );

    test('rejects unauthenticated status calls', () async {
      await expectLater(
        endpoints.control.status(sessionBuilder),
        throwsA(isA<ServerpodUnauthenticatedException>()),
      );
    });

    test('authenticates only the configured bootstrap token', () async {
      final authenticator = DexteroTokenAuthenticator('a' * 32);
      final session = sessionBuilder.build();

      final accepted = await authenticator.authenticate(session, 'a' * 32);
      final rejected = await authenticator.authenticate(session, 'b' * 32);

      expect(accepted?.userIdentifier, 'dextero-controller');
      expect(rejected, isNull);
      await session.close();
    });

    test('reports a database-free in-memory host', () async {
      final status = await endpoints.control.status(authenticatedSession);

      expect(status.name, 'Dextero');
      expect(status.persistence, 'memory');
      expect(status.databaseRequired, isFalse);
      expect(status.streamingAvailable, isTrue);
      expect(status.startedAt.isUtc, isTrue);
    });

    test('streams a complete ordered core task lifecycle', () async {
      final events = await endpoints.control
          .runTask(authenticatedSession, 'Inspect the workspace')
          .toList();

      expect(events, hasLength(4));
      expect(events.map((event) => event.sequence), [0, 1, 2, 3]);
      expect(events.first.kind, TaskEventKind.queued);
      expect(events.last.kind, TaskEventKind.completed);
      expect(events.last.terminal, isTrue);
      expect(events.map((event) => event.taskId).toSet(), hasLength(1));
    });

    test('rejects empty task prompts', () async {
      await expectLater(
        endpoints.control.runTask(authenticatedSession, '   '),
        emitsError(isA<ArgumentError>()),
      );
    });
  });
}

final class _FakeTaskRunner implements TaskRunner {
  @override
  Stream<CoreTaskEvent> run(String prompt) async* {
    const kinds = [
      CoreTaskEventKind.queued,
      CoreTaskEventKind.running,
      CoreTaskEventKind.output,
      CoreTaskEventKind.completed,
    ];
    for (var sequence = 0; sequence < kinds.length; sequence++) {
      yield CoreTaskEvent(
        taskId: 'task-test',
        sequence: sequence,
        kind: kinds[sequence],
        message: sequence == 2 ? 'Workspace inspected' : kinds[sequence].name,
        timestamp: DateTime.utc(2026),
        terminal: sequence == kinds.length - 1,
      );
    }
  }
}
