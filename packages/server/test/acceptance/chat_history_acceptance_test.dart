import 'package:dextero_core/dextero_core.dart' as core;
import 'package:dextero_server/src/control/chat_runtime.dart';
import 'package:dextero_server/src/generated/protocol.dart';
import 'package:test/test.dart';

import '../integration/test_tools/serverpod_test_tools.dart';
import '../integration/test_tools/test_server_config.dart';

void main() {
  late core.InMemoryChatHistoryStore store;
  late core.ChatService service;
  late String conversationId;

  setUp(() async {
    store = core.InMemoryChatHistoryStore();
    service = core.ChatService(store: store, agent: _AcceptanceAgent());
    conversationId = (await service.createConversation()).id;
    ChatRuntime.configure(
      chatService: service,
      defaultConversationId: conversationId,
    );
  });

  tearDown(() => store.close());

  withServerpod('Chat history acceptance', (sessionBuilder, endpoints) {
    final controller = sessionBuilder.copyWith(
      authentication: AuthenticationOverride.authenticationInfo(
        'acceptance-controller',
        const {},
      ),
    );

    test(
      'crosses core, store, endpoint, and generated client models',
      () async {
        final status = await endpoints.control.status(controller);
        expect(status.conversationId, conversationId);

        final accepted = await endpoints.control.submitMessage(
          controller,
          ChatSubmitRequest(
            conversationId: status.conversationId,
            message: 'Hello Dextero',
            correlationId: 'acceptance-1',
          ),
        );
        final received = await endpoints.control
            .streamHistory(controller, conversationId, -1)
            .take(5)
            .toList();

        expect(accepted.userEntry.content, 'Hello Dextero');
        expect(received.map((entry) => entry.kind), [
          ChatEntryKind.userMessage,
          ChatEntryKind.lifecycle,
          ChatEntryKind.lifecycle,
          ChatEntryKind.assistantMessage,
          ChatEntryKind.lifecycle,
        ]);
        expect(received.map((entry) => entry.sequence), [0, 1, 2, 3, 4]);
        expect(received.map((entry) => entry.eventVersion).toSet(), {1});
        expect(received.first.family, ChatEventFamily.message);
        expect(received[1].family, ChatEventFamily.task);
        expect(received[3].family, ChatEventFamily.model);
        expect(received.map((entry) => entry.correlationId).toSet(), {
          'acceptance-1',
        });

        final fetched = await endpoints.control.history(
          controller,
          conversationId,
        );
        expect(
          fetched.map((entry) => entry.entryId),
          received.map((entry) => entry.entryId),
        );
      },
    );
  }, configOverride: useEphemeralApiPort);
}

final class _AcceptanceAgent implements core.ConversationAgent {
  @override
  Future<core.ConversationAgentResult> run(
    String prompt, {
    required core.ConversationAgentEventSink onEvent,
    required core.CancellationToken cancellationToken,
  }) async {
    await onEvent(
      core.ConversationAgentEvent(
        kind: core.ConversationAgentEventKind.lifecycle,
        summary: core.SafeMetadata.text('Codex is working'),
      ),
    );
    await onEvent(
      core.ConversationAgentEvent(
        kind: core.ConversationAgentEventKind.assistantMessage,
        summary: core.SafeMetadata.text('Hello from Dextero'),
      ),
    );
    return const core.ConversationAgentResult(output: 'Hello from Dextero');
  }
}
