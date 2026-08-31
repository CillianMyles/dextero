import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'chat_service.dart';
import 'safe_metadata.dart';
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
    required this.turnId,
    required this.toolCalls,
  });

  final String output;
  final String threadId;
  final String turnId;
  final int toolCalls;
}

enum CodexAgentActivityKind {
  lifecycle,
  assistantMessage,
  toolCallStarted,
  toolCallCompleted,
  error,
}

final class CodexAgentActivity {
  const CodexAgentActivity({
    required this.kind,
    required this.summary,
    this.toolCallId,
    this.toolName,
    this.success,
    this.retrying = false,
  });

  final CodexAgentActivityKind kind;
  final SafeSummary summary;
  final String? toolCallId;
  final String? toolName;
  final bool? success;
  final bool retrying;
}

typedef CodexAgentActivitySink =
    FutureOr<void> Function(CodexAgentActivity activity);

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

  Future<CodexAgentRun> run(
    String prompt, {
    required List<Tool> tools,
    CodexAgentActivitySink? onActivity,
  }) async {
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
            'Use the host-provided dynamic tools for file and command operations. '
            'Use run_command for normal CLI execution. Use run_shell only when '
            'shell syntax is required. '
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
      final turnResponse = await _waitForResponse(messages, 2);
      final turn = turnResponse['turn'];
      if (turn is! Map || turn['id'] is! String) {
        throw const FormatException('turn/start response omitted turn.id');
      }
      final turnId = turn['id']! as String;
      await onActivity?.call(
        CodexAgentActivity(
          kind: CodexAgentActivityKind.lifecycle,
          summary: SafeMetadata.text('Codex is working'),
        ),
      );

      String? output;
      String? lastError;
      var toolCallCount = 0;
      final startedToolCalls = <String>{};
      final completedToolCalls = <String>{};
      while (await _moveNext(messages)) {
        final message = messages.current;
        final method = message['method'];
        final params = message['params'];
        if (method == 'item/tool/call' && message.containsKey('id')) {
          toolCallCount++;
          final request = _toolRequest(message['id'], params);
          if (startedToolCalls.add(request.callId)) {
            await onActivity?.call(
              CodexAgentActivity(
                kind: CodexAgentActivityKind.toolCallStarted,
                summary: SafeMetadata.toolCall(
                  request.toolName,
                  request.arguments,
                ),
                toolCallId: request.callId,
                toolName: request.toolName,
              ),
            );
          }
          final execution = await _handleToolCall(
            transport,
            requestId: message['id'],
            params: params,
            tools: toolsByName,
          );
          if (completedToolCalls.add(execution.callId)) {
            await onActivity?.call(
              CodexAgentActivity(
                kind: CodexAgentActivityKind.toolCallCompleted,
                summary: SafeMetadata.toolResult(
                  execution.toolName,
                  execution.content,
                  success: execution.success,
                ),
                toolCallId: execution.callId,
                toolName: execution.toolName,
                success: execution.success,
              ),
            );
          }
          continue;
        }
        if (method == 'item/started' && params is Map) {
          final activity = _toolItemActivity(params['item'], completed: false);
          if (activity != null && startedToolCalls.add(activity.toolCallId!)) {
            await onActivity?.call(activity);
          }
          continue;
        }
        if (method == 'item/completed' && params is Map) {
          final item = params['item'];
          if (item is Map &&
              item['type'] == 'agentMessage' &&
              item['text'] is String) {
            output = item['text']! as String;
            await onActivity?.call(
              CodexAgentActivity(
                kind: CodexAgentActivityKind.assistantMessage,
                summary: SafeMetadata.message(output),
              ),
            );
          } else {
            final activity = _toolItemActivity(item, completed: true);
            if (activity != null &&
                completedToolCalls.add(activity.toolCallId!)) {
              await onActivity?.call(activity);
            }
          }
          continue;
        }
        if (method == 'error' && params is Map) {
          final error = params['error'];
          lastError = error is Map
              ? error['message']?.toString()
              : error.toString();
          final retrying = params['willRetry'] == true;
          await onActivity?.call(
            CodexAgentActivity(
              kind: CodexAgentActivityKind.error,
              summary: SafeMetadata.text(
                retrying
                    ? 'Codex reported a temporary error and will retry: '
                          '${lastError ?? 'Unknown error'}'
                    : lastError ?? 'Codex reported an error',
              ),
              retrying: retrying,
            ),
          );
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
            turnId: turnId,
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

  Future<_ToolExecution> _handleToolCall(
    CodexAppServerTransport transport, {
    required Object? requestId,
    required Object? params,
    required Map<String, Tool> tools,
  }) async {
    var success = false;
    Object? content;
    var toolName = 'unknown_tool';
    var callId = requestId.toString();
    var arguments = <String, Object?>{};
    if (params is! Map || params['tool'] is! String) {
      content = 'Malformed dynamic tool request.';
    } else {
      final name = params['tool']! as String;
      toolName = name;
      if (params['callId'] is String) callId = params['callId']! as String;
      final tool = tools[name];
      final rawArguments = params['arguments'];
      if (tool == null) {
        content = 'Unknown dynamic tool: $name';
      } else if (rawArguments is! Map) {
        content = 'Tool arguments must be a JSON object.';
      } else {
        arguments = rawArguments.cast<String, Object?>();
        try {
          content = await tool.call(arguments);
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
    return _ToolExecution(
      callId: callId,
      toolName: toolName,
      arguments: arguments,
      content: content,
      success: success,
    );
  }

  _ToolRequest _toolRequest(Object? requestId, Object? params) {
    if (params is! Map) {
      return _ToolRequest(
        callId: requestId.toString(),
        toolName: 'unknown_tool',
        arguments: const {},
      );
    }
    return _ToolRequest(
      callId: params['callId'] is String
          ? params['callId']! as String
          : requestId.toString(),
      toolName: params['tool'] is String
          ? params['tool']! as String
          : 'unknown_tool',
      arguments: params['arguments'] is Map
          ? (params['arguments']! as Map).cast<String, Object?>()
          : const {},
    );
  }

  CodexAgentActivity? _toolItemActivity(
    Object? rawItem, {
    required bool completed,
  }) {
    if (rawItem is! Map || rawItem['id'] is! String) return null;
    final id = rawItem['id']! as String;
    final type = rawItem['type'];
    final status = rawItem['status']?.toString();
    final success = status == null
        ? completed
        : !{'failed', 'declined', 'error'}.contains(status);
    final (toolName, summary) = switch (type) {
      'dynamicToolCall' => (
        rawItem['tool'] is String ? rawItem['tool']! as String : 'dynamic_tool',
        completed
            ? SafeMetadata.toolResult(
                rawItem['tool'] is String
                    ? rawItem['tool']! as String
                    : 'dynamic_tool',
                null,
                success: success,
              )
            : SafeMetadata.toolCall(
                rawItem['tool'] is String
                    ? rawItem['tool']! as String
                    : 'dynamic_tool',
                rawItem['arguments'] is Map
                    ? (rawItem['arguments']! as Map).cast<String, Object?>()
                    : const {},
              ),
      ),
      'commandExecution' => (
        'command_execution',
        SafeMetadata.text(
          completed
              ? 'Command execution ${success ? 'completed' : 'failed'}'
              : 'Command execution started',
        ),
      ),
      'fileChange' => (
        'file_change',
        SafeMetadata.text(
          completed
              ? 'File change ${success ? 'completed' : 'failed'}'
              : 'File change started',
        ),
      ),
      'mcpToolCall' => (
        rawItem['tool'] is String ? rawItem['tool']! as String : 'mcp_tool',
        SafeMetadata.text(
          completed
              ? 'MCP tool ${success ? 'completed' : 'failed'}'
              : 'MCP tool started',
        ),
      ),
      'webSearch' => (
        'web_search',
        SafeMetadata.text(
          completed ? 'Web search completed' : 'Web search started',
        ),
      ),
      _ => (null, null),
    };
    if (toolName == null || summary == null) return null;
    return CodexAgentActivity(
      kind: completed
          ? CodexAgentActivityKind.toolCallCompleted
          : CodexAgentActivityKind.toolCallStarted,
      summary: summary,
      toolCallId: id,
      toolName: toolName,
      success: completed ? success : null,
    );
  }

  String _encodeToolContent(Object? content) {
    try {
      return jsonEncode(content);
    } on JsonUnsupportedObjectError {
      return content.toString();
    }
  }
}

final class CodexConversationAgent implements ConversationAgent {
  CodexConversationAgent({
    required CodexAppServerAgent agent,
    required List<Tool> tools,
  }) : _agent = agent,
       _tools = List.unmodifiable(tools);

  final CodexAppServerAgent _agent;
  final List<Tool> _tools;

  @override
  Future<ConversationAgentResult> run(
    String prompt, {
    required ConversationAgentEventSink onEvent,
  }) async {
    final result = await _agent.run(
      prompt,
      tools: _tools,
      onActivity: (activity) => onEvent(
        ConversationAgentEvent(
          kind: switch (activity.kind) {
            CodexAgentActivityKind.lifecycle =>
              ConversationAgentEventKind.lifecycle,
            CodexAgentActivityKind.assistantMessage =>
              ConversationAgentEventKind.assistantMessage,
            CodexAgentActivityKind.toolCallStarted =>
              ConversationAgentEventKind.toolCallStarted,
            CodexAgentActivityKind.toolCallCompleted =>
              ConversationAgentEventKind.toolCallCompleted,
            CodexAgentActivityKind.error => ConversationAgentEventKind.error,
          },
          summary: activity.summary,
          toolCallId: activity.toolCallId,
          toolName: activity.toolName,
          success: activity.success,
          retrying: activity.retrying,
        ),
      ),
    );
    return ConversationAgentResult(output: result.output);
  }
}

final class _ToolExecution {
  const _ToolExecution({
    required this.callId,
    required this.toolName,
    required this.arguments,
    required this.content,
    required this.success,
  });

  final String callId;
  final String toolName;
  final JsonMap arguments;
  final Object? content;
  final bool success;
}

final class _ToolRequest {
  const _ToolRequest({
    required this.callId,
    required this.toolName,
    required this.arguments,
  });

  final String callId;
  final String toolName;
  final JsonMap arguments;
}
