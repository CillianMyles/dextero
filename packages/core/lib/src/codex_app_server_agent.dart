import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'tool.dart';

typedef CodexTransportFactory = Future<CodexAppServerTransport> Function();

abstract interface class CodexAppServerTransport {
  Stream<JsonMap> get messages;

  Future<void> send(JsonMap message);

  Future<void> close();
}

final class ProcessCodexAppServerTransport implements CodexAppServerTransport {
  ProcessCodexAppServerTransport._(this._process)
    : _messages = _process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .where((line) => line.trim().isNotEmpty)
          .map(_decodeMessage) {
    _process.stderr.drain<void>();
  }

  final Process _process;
  final Stream<JsonMap> _messages;
  var _closed = false;

  static Future<ProcessCodexAppServerTransport> start({
    String executable = 'codex',
    String? workingDirectory,
  }) async {
    final process = await Process.start(
      executable,
      ['app-server'],
      workingDirectory: workingDirectory,
      runInShell: false,
    );
    return ProcessCodexAppServerTransport._(process);
  }

  @override
  Stream<JsonMap> get messages => _messages;

  @override
  Future<void> send(JsonMap message) async {
    if (_closed) {
      throw StateError('Codex app-server transport is closed.');
    }
    _process.stdin.writeln(jsonEncode(message));
    await _process.stdin.flush();
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _process.stdin.close();
    _process.kill();
    await _process.exitCode;
  }

  static JsonMap _decodeMessage(String line) {
    final decoded = jsonDecode(line);
    if (decoded is! Map) {
      throw const FormatException('Codex app-server emitted non-object JSON.');
    }
    return decoded.cast<String, Object?>();
  }
}

final class CodexAgentRun {
  const CodexAgentRun({
    required this.output,
    required this.threadId,
    required this.toolCalls,
  });

  final String output;
  final String threadId;
  final int toolCalls;
}

/// Runs host-provided tools through Codex app-server's dynamic-tool protocol.
///
/// The app server owns ChatGPT subscription login and token refresh. Dynamic
/// tools are experimental in the current Codex protocol, so this adapter keeps
/// that dependency isolated from the provider-neutral [Tool] contract.
final class CodexAppServerAgent {
  CodexAppServerAgent({
    this.model,
    this.workingDirectory,
    this.messageTimeout = const Duration(minutes: 5),
    String codexExecutable = 'codex',
    CodexTransportFactory? transportFactory,
  }) : _transportFactory =
           transportFactory ??
           (() => ProcessCodexAppServerTransport.start(
             executable: codexExecutable,
             workingDirectory: workingDirectory,
           ));

  final String? model;
  final String? workingDirectory;
  final Duration messageTimeout;
  final CodexTransportFactory _transportFactory;

  Future<CodexAgentRun> run(String prompt, {required List<Tool> tools}) async {
    if (prompt.trim().isEmpty) {
      throw ArgumentError.value(prompt, 'prompt', 'must not be empty');
    }
    final toolsByName = {for (final tool in tools) tool.definition.name: tool};
    if (toolsByName.length != tools.length) {
      throw ArgumentError('Tool names must be unique.');
    }

    final transport = await _transportFactory();
    final messages = StreamIterator(transport.messages);
    try {
      await transport.send({
        'method': 'initialize',
        'id': 0,
        'params': {
          'clientInfo': {
            'name': 'dextero',
            'title': 'Dextero',
            'version': '0.0.1',
          },
          'capabilities': {'experimentalApi': true},
        },
      });
      await _waitForResponse(messages, 0);
      await transport.send({
        'method': 'initialized',
        'params': <String, Object?>{},
      });

      final threadParams = <String, Object?>{
        'ephemeral': true,
        'sandbox': 'read-only',
        'approvalPolicy': 'never',
        'dynamicTools': [
          for (final tool in tools)
            {
              'type': 'function',
              'name': tool.definition.name,
              'description': tool.definition.description,
              'inputSchema': tool.definition.inputSchema,
            },
        ],
        'developerInstructions':
            'Use the host-provided dynamic tools for file and shell operations. '
            'Do not substitute built-in file or command tools for them.',
      };
      if (model != null) threadParams['model'] = model;
      if (workingDirectory != null) threadParams['cwd'] = workingDirectory;
      await transport.send({
        'method': 'thread/start',
        'id': 1,
        'params': threadParams,
      });
      final threadResponse = await _waitForResponse(messages, 1);
      final thread = threadResponse['thread'];
      if (thread is! Map || thread['id'] is! String) {
        throw const FormatException('thread/start response omitted thread.id');
      }
      final threadId = thread['id']! as String;

      await transport.send({
        'method': 'turn/start',
        'id': 2,
        'params': {
          'threadId': threadId,
          'input': [
            {'type': 'text', 'text': prompt},
          ],
        },
      });
      await _waitForResponse(messages, 2);

      String? output;
      String? lastError;
      var toolCallCount = 0;
      while (await _moveNext(messages)) {
        final message = messages.current;
        final method = message['method'];
        final params = message['params'];
        if (method == 'item/tool/call' && message.containsKey('id')) {
          toolCallCount++;
          await _handleToolCall(
            transport,
            requestId: message['id'],
            params: params,
            tools: toolsByName,
          );
          continue;
        }
        if (method == 'item/completed' && params is Map) {
          final item = params['item'];
          if (item is Map &&
              item['type'] == 'agentMessage' &&
              item['text'] is String) {
            output = item['text']! as String;
          }
          continue;
        }
        if (method == 'error' && params is Map) {
          final error = params['error'];
          lastError = error is Map
              ? error['message']?.toString()
              : error.toString();
          continue;
        }
        if (method == 'turn/completed' && params is Map) {
          final turn = params['turn'];
          final status = turn is Map ? turn['status'] : null;
          if (status != 'completed') {
            throw StateError(
              lastError ?? 'Codex turn ended with status $status',
            );
          }
          if (output == null || output.trim().isEmpty) {
            throw StateError(
              'Codex turn completed without a final agent message.',
            );
          }
          return CodexAgentRun(
            output: output,
            threadId: threadId,
            toolCalls: toolCallCount,
          );
        }
      }
      throw StateError('Codex app-server closed before the turn completed.');
    } finally {
      await messages.cancel();
      await transport.close();
    }
  }

  Future<JsonMap> _waitForResponse(
    StreamIterator<JsonMap> messages,
    Object requestId,
  ) async {
    while (await _moveNext(messages)) {
      final message = messages.current;
      if (message['id'] != requestId) continue;
      if (message['error'] case final Map error) {
        throw StateError(
          'Codex app-server request failed: ${error['message'] ?? error}',
        );
      }
      final result = message['result'];
      if (result is! Map) {
        throw const FormatException(
          'Codex app-server response omitted result.',
        );
      }
      return result.cast<String, Object?>();
    }
    throw StateError(
      'Codex app-server closed while waiting for request $requestId.',
    );
  }

  Future<bool> _moveNext(StreamIterator<JsonMap> messages) =>
      messages.moveNext().timeout(messageTimeout);

  Future<void> _handleToolCall(
    CodexAppServerTransport transport, {
    required Object? requestId,
    required Object? params,
    required Map<String, Tool> tools,
  }) async {
    var success = false;
    Object? content;
    if (params is! Map || params['tool'] is! String) {
      content = 'Malformed dynamic tool request.';
    } else {
      final name = params['tool']! as String;
      final tool = tools[name];
      final rawArguments = params['arguments'];
      if (tool == null) {
        content = 'Unknown dynamic tool: $name';
      } else if (rawArguments is! Map) {
        content = 'Tool arguments must be a JSON object.';
      } else {
        try {
          content = await tool.call(rawArguments.cast<String, Object?>());
          success = true;
        } on Object catch (error) {
          content = error.toString();
        }
      }
    }

    await transport.send({
      'id': requestId,
      'result': {
        'contentItems': [
          {'type': 'inputText', 'text': _encodeToolContent(content)},
        ],
        'success': success,
      },
    });
  }

  String _encodeToolContent(Object? content) {
    try {
      return jsonEncode(content);
    } on JsonUnsupportedObjectError {
      return content.toString();
    }
  }
}
