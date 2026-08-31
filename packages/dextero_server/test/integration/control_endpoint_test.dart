import 'package:dextero_server/src/auth/dextero_token_authenticator.dart';
import 'package:dextero_server/src/generated/protocol.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

void main() {
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

    test('streams a complete ordered demo lifecycle', () async {
      final events = await endpoints.control
          .runDemo(authenticatedSession, 3)
          .toList();

      expect(events, hasLength(5));
      expect(events.map((event) => event.sequence), [0, 1, 2, 3, 4]);
      expect(events.first.kind, TaskEventKind.queued);
      expect(events.last.kind, TaskEventKind.completed);
      expect(events.last.terminal, isTrue);
      expect(events.map((event) => event.taskId).toSet(), hasLength(1));
    });

    test('rejects unbounded demo streams', () async {
      await expectLater(
        endpoints.control.runDemo(authenticatedSession, 21),
        emitsError(isA<ArgumentError>()),
      );
    });
  });
}
