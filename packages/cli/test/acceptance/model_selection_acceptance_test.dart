import 'dart:async';
import 'dart:io';

import 'package:dextero_cli/dextero_cli.dart';
import 'package:dextero_core/dextero_core.dart';
import 'package:dextero_server/dextero_server.dart';
import 'package:test/test.dart';

void main() {
  for (final selected in [
    'gemini:gemini-2.5-flash',
    'codex:gpt-5.3-codex-spark',
    'codex:default',
  ]) {
    test(
      'CLI selects $selected through HTTP and runs the production adapter',
      () async {
        final configuration = AgentRuntimeConfiguration.fromEnvironment(const {
          'GEMINI_API_KEY': 'test-only-key',
        });
        final gemini = _GeminiTransport();
        final codex = _CodexTransport();
        ConversationAgent agentFor(String id) {
          final option = configuration.availableOptions.singleWhere(
            (option) => option.id == id,
          );
          return configuration.createAgent(
            workspace: Directory.current.path,
            provider: option.provider,
            modelName: option.modelName,
            geminiTransport: gemini,
            codexTransportFactory: () async => codex,
          );
        }

        final store = InMemoryChatHistoryStore();
        final service = ChatService(
          store: store,
          agent: agentFor(configuration.selectedModelId),
        );
        final conversation = await service.createConversation();
        final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final port = probe.port;
        await probe.close();
        const token = 'selection-acceptance-token-01234567890123456789';
        final pod = await startControlServer(
          token: token,
          chatService: service,
          defaultConversationId: conversation.id,
          apiPort: port,
          runInGuardedZone: false,
          modelProvider: configuration.providerName,
          modelName: configuration.modelName,
          availableModels: configuration.availableModels,
          modelOptions: configuration.availableOptions,
          modelSelector: (id) => service.selectAgent(
            conversationId: conversation.id,
            agent: agentFor(id),
          ),
        );
        addTearDown(() async {
          await pod.shutdown(exitProcess: false);
          await store.close();
        });
        final observer = ServerpodTerminalChatClient(
          serverUrl: 'http://localhost:$port/',
          token: token,
        );
        addTearDown(observer.close);
        final initial = await observer.status();
        expect(initial.modelProvider, 'gemini');
        expect(initial.modelOptions.map((option) => option.id), [
          'gemini:gemini-2.5-flash',
          'codex:gpt-5.3-codex-spark',
          'codex:default',
        ]);
        // Switch away and back before submitting to exercise both directions.
        await observer.selectModel('codex:default');
        final io = _Io();
        final result =
            await TerminalChat(
              client: ServerpodTerminalChatClient(
                serverUrl: 'http://localhost:$port/',
                token: token,
              ),
              io: io,
            ).run(
              initialMessage: 'Identify the chosen adapter',
              modelName: selected,
            );
        expect(result, 0, reason: io.errors.join('\n'));
        final status = await observer.status();
        expect('${status.modelProvider}:${status.modelName}', selected);
        if (selected.startsWith('gemini:')) {
          expect(gemini.models, ['gemini-2.5-flash']);
          expect(codex.threadParams, isNull);
        } else {
          expect(gemini.models, isEmpty);
          expect(
            codex.threadParams!['model'],
            selected == 'codex:default' ? null : codexSparkModel,
          );
          expect(codex.threadParams!['dynamicTools'], hasLength(5));
        }
        final history = await store.history(conversation.id);
        expect(
          history
              .where((entry) => entry.kind == ChatEntryKind.assistantMessage)
              .single
              .content,
          selected.startsWith('gemini:')
              ? 'Gemini adapter replied'
              : 'Codex adapter replied',
        );
        await expectLater(
          observer.selectModel(
            selected.startsWith('gemini:')
                ? 'codex:default'
                : 'gemini:gemini-2.5-flash',
          ),
          throwsA(anything),
        );
        expect((await observer.status()).modelProvider, status.modelProvider);
      },
    );
  }
}

final class _GeminiTransport implements GeminiTransport {
  final models = <String>[];
  @override
  Future<JsonMap> generateContent({
    required String model,
    required JsonMap request,
    CancellationToken? cancellationToken,
  }) async {
    models.add(model);
    expect(request['tools'], isNotEmpty);
    return {
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': 'Gemini adapter replied'},
            ],
          },
        },
      ],
    };
  }
}

final class _CodexTransport implements CodexAppServerTransport {
  final _messages = StreamController<JsonMap>();
  JsonMap? threadParams;
  @override
  Stream<JsonMap> get messages => _messages.stream;
  @override
  Future<void> close() => _messages.close();
  @override
  Future<void> send(JsonMap message) async {
    switch (message['method']) {
      case 'initialize':
        _messages.add({'id': 0, 'result': <String, Object?>{}});
      case 'thread/start':
        threadParams = message['params']! as JsonMap;
        _messages.add({
          'id': 1,
          'result': {
            'thread': {'id': 'thread-test'},
          },
        });
      case 'turn/start':
        _messages.add({
          'id': 2,
          'result': {
            'turn': {'id': 'turn-test'},
          },
        });
        _messages.add({
          'method': 'item/completed',
          'params': {
            'item': {'type': 'agentMessage', 'text': 'Codex adapter replied'},
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
}

final class _Io implements TerminalIo {
  final errors = <String>[];
  @override
  bool get hasInputTerminal => false;
  @override
  bool get hasOutputTerminal => false;
  @override
  String? readLine() => null;
  @override
  void write(String value) {}
  @override
  void writeln(String value) {}
  @override
  void error(String value) => errors.add(value);
}
