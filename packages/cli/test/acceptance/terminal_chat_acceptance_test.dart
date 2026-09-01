import 'package:dextero_cli/dextero_cli.dart';
import 'package:dextero_core/dextero_core.dart';
import 'package:dextero_server/dextero_server.dart';
import 'package:test/test.dart';

void main() {
  test(
    'one-shot terminal chat crosses the real server and canonical core store',
    () async {
      const token = 'acceptance-token-0123456789-0123456789';
      final store = InMemoryChatHistoryStore();
      final service = ChatService(store: store, agent: _AcceptanceAgent());
      final conversation = await service.createConversation();
      final pod = await startControlServer(
        token: token,
        chatService: service,
        defaultConversationId: conversation.id,
        apiPort: 0,
        runInGuardedZone: false,
      );
      addTearDown(() async {
        await pod.shutdown(exitProcess: false);
        await store.close();
      });
      final io = _AcceptanceIo();
      final chat = TerminalChat(
        client: ServerpodTerminalChatClient(
          serverUrl: 'http://localhost:${pod.server.port}/',
          token: token,
        ),
        io: io,
        correlationIdFactory: () => 'acceptance-cli-1',
      );

      final exitCode = await chat.run(initialMessage: 'Inspect the workspace');

      expect(exitCode, 0);
      expect(io.errors, isEmpty);
      expect(io.output.join(), contains('[you] Inspect the workspace'));
      expect(io.output.join(), contains('[list_files] list_files started'));
      expect(io.output.join(), contains('[dextero] Workspace\nready'));
      final history = await store.history(conversation.id);
      expect(history.map((entry) => entry.sequence), [0, 1, 2, 3, 4, 5, 6]);
      expect(history.map((entry) => entry.kind), [
        ChatEntryKind.userMessage,
        ChatEntryKind.lifecycle,
        ChatEntryKind.lifecycle,
        ChatEntryKind.toolCall,
        ChatEntryKind.toolResult,
        ChatEntryKind.assistantMessage,
        ChatEntryKind.lifecycle,
      ]);
      expect(history.map((entry) => entry.correlationId).toSet(), {
        'acceptance-cli-1',
      });
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

final class _AcceptanceAgent implements ConversationAgent {
  @override
  Future<ConversationAgentResult> run(
    String prompt, {
    required ConversationAgentEventSink onEvent,
    required CancellationToken cancellationToken,
  }) async {
    await onEvent(
      ConversationAgentEvent(
        kind: ConversationAgentEventKind.lifecycle,
        summary: SafeMetadata.text('Codex is working'),
      ),
    );
    await onEvent(
      ConversationAgentEvent(
        kind: ConversationAgentEventKind.toolCallStarted,
        summary: SafeMetadata.toolCall('list_files', const {}),
        toolCallId: 'acceptance-tool-1',
        toolName: 'list_files',
      ),
    );
    await onEvent(
      ConversationAgentEvent(
        kind: ConversationAgentEventKind.toolCallCompleted,
        summary: SafeMetadata.toolResult('list_files', const {
          'entries': <Object>[],
        }, success: true),
        toolCallId: 'acceptance-tool-1',
        toolName: 'list_files',
        success: true,
      ),
    );
    await onEvent(
      ConversationAgentEvent(
        kind: ConversationAgentEventKind.assistantMessage,
        summary: SafeMetadata.message('Workspace\nready'),
      ),
    );
    return const ConversationAgentResult(output: 'Workspace\nready');
  }
}

final class _AcceptanceIo implements TerminalIo {
  final output = <String>[];
  final errors = <String>[];

  @override
  bool get hasTerminal => false;

  @override
  void error(String value) => errors.add(value);

  @override
  String? readLine() => null;

  @override
  void write(String value) => output.add(value);

  @override
  void writeln(String value) => output.add('$value\n');
}
