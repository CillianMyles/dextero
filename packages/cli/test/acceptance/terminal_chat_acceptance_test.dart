import 'dart:io';

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
      final service = ChatService(
        store: store,
        agent: ModelConversationAgent(
          model: GeminiModel(transport: _AcceptanceGeminiTransport()),
          tools: [_AcceptanceRunCommandTool(), _AcceptanceReadFileTool()],
          providerName: 'Gemini',
        ),
      );
      final conversation = await service.createConversation();
      final portProbe = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final apiPort = portProbe.port;
      await portProbe.close();
      final pod = await startControlServer(
        token: token,
        chatService: service,
        defaultConversationId: conversation.id,
        modelProvider: 'gemini',
        modelName: defaultGeminiModel,
        apiPort: apiPort,
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
      expect(io.output.join(), contains('gemini · gemini-3.7-flash'));
      expect(io.output.join(), contains('[you] Inspect the workspace'));
      expect(
        io.output.join(),
        contains('[run_command] run_command started: printf "workspace ready"'),
      );
      expect(
        io.output.join(),
        contains('[run_command] run_command stdout: 15 bytes'),
      );
      expect(io.output.join(), contains('stdout:\nworkspace ready'));
      expect(
        io.output.join(),
        contains('[read_file] read_file failed: File not found: missing.txt'),
      );
      expect(io.output.join(), contains('[dextero] Workspace\nready'));
      final history = await store.history(conversation.id);
      expect(history.map((entry) => entry.sequence), [
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
      ]);
      expect(history.map((entry) => entry.kind), [
        ChatEntryKind.userMessage,
        ChatEntryKind.lifecycle,
        ChatEntryKind.lifecycle,
        ChatEntryKind.toolCall,
        ChatEntryKind.toolOutput,
        ChatEntryKind.toolResult,
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

final class _AcceptanceGeminiTransport implements GeminiTransport {
  var _turn = 0;

  @override
  Future<JsonMap> generateContent({
    required String model,
    required JsonMap request,
    CancellationToken? cancellationToken,
  }) async {
    final turn = _turn++;
    if (turn == 0) {
      return {
        'candidates': [
          {
            'content': {
              'parts': [
                {
                  'functionCall': {
                    'id': 'acceptance-tool-1',
                    'name': 'run_command',
                    'args': {
                      'command': 'printf',
                      'arguments': ['workspace ready'],
                    },
                  },
                  'thoughtSignature': 'acceptance-signature',
                },
              ],
            },
          },
        ],
      };
    }
    final toolResponse = _lastToolResponse(request);
    if (turn == 1) {
      expect(toolResponse['id'], 'acceptance-tool-1');
      return {
        'candidates': [
          {
            'content': {
              'parts': [
                {
                  'functionCall': {
                    'id': 'acceptance-tool-2',
                    'name': 'read_file',
                    'args': {'path': 'missing.txt'},
                  },
                  'thoughtSignature': 'acceptance-signature-2',
                },
              ],
            },
          },
        ],
      };
    }
    expect(toolResponse['id'], 'acceptance-tool-2');
    return {
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': 'Workspace\nready'},
            ],
          },
        },
      ],
    };
  }

  Map _lastToolResponse(JsonMap request) {
    final contents = request['contents']! as List;
    return ((((contents.last as Map)['parts'] as List).single
            as Map)['functionResponse']
        as Map);
  }
}

final class _AcceptanceRunCommandTool implements Tool {
  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'run_command',
    description: 'Run a command.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'command': {'type': 'string'},
        'arguments': {
          'type': 'array',
          'items': {'type': 'string'},
        },
      },
      'additionalProperties': false,
    },
  );

  @override
  Future<Object?> call(
    JsonMap arguments, {
    CancellationToken? cancellationToken,
    ToolOutputSink? onOutput,
  }) async {
    if (onOutput != null) {
      await onOutput(const ToolOutputUpdate(stream: 'stdout', byteCount: 15));
    }
    return const {
      'exit_code': 0,
      'stdout': 'workspace ready',
      'stderr': '',
      'truncated': false,
    };
  }
}

final class _AcceptanceReadFileTool implements Tool {
  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'read_file',
    description: 'Read a file.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'path': {'type': 'string'},
      },
      'additionalProperties': false,
    },
  );

  @override
  Object? call(
    JsonMap arguments, {
    CancellationToken? cancellationToken,
    ToolOutputSink? onOutput,
  }) => throw const _AcceptanceToolError('File not found: missing.txt');
}

final class _AcceptanceToolError implements Exception {
  const _AcceptanceToolError(this.message);

  final String message;

  @override
  String toString() => message;
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
