import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'approval.dart';
import 'cancellation.dart';
import 'chat_service.dart';
import 'process_environment.dart';
import 'safe_metadata.dart';
import 'tool.dart';

const claudeCodeSubscriptionAuthSource = 'local Claude Code subscription';

/// The MCP server name under which Dextero's tools are offered to Claude Code.
const claudeCodeToolServer = 'dextero';
const _toolPrefix = 'mcp__${claudeCodeToolServer}__';

typedef ClaudeCodeTransportFactory =
    Future<ClaudeCodeTransport> Function(List<String> arguments);

/// Line-delimited stream-json messages exchanged with `claude --print`.
abstract interface class ClaudeCodeTransport {
  Stream<JsonMap> get messages;

  /// Bounded recent stderr, used only to explain an unexpected exit.
  String get diagnostics;

  Future<void> send(JsonMap message);

  Future<void> close();
}

final class ProcessClaudeCodeTransport implements ClaudeCodeTransport {
  ProcessClaudeCodeTransport._(this._process)
    : _messages = _process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .where((line) => line.trim().isNotEmpty)
          .map(_decodeMessage) {
    _process.stderr.transform(utf8.decoder).listen((chunk) {
      _stderr.write(chunk);
      if (_stderr.length > _diagnosticLimit) {
        final text = _stderr.toString();
        _stderr
          ..clear()
          ..write(text.substring(text.length - _diagnosticLimit));
      }
    }, onError: (_) {});
  }

  static const _diagnosticLimit = 4000;

  final Process _process;
  final Stream<JsonMap> _messages;
  final _stderr = StringBuffer();
  var _closed = false;

  static Future<ProcessClaudeCodeTransport> start(
    List<String> arguments, {
    String executable = 'claude',
    String? workingDirectory,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      runInShell: false,
      includeParentEnvironment: false,
      environment: claudeCodeProcessEnvironment(),
    );
    return ProcessClaudeCodeTransport._(process);
  }

  @override
  Stream<JsonMap> get messages => _messages;

  @override
  String get diagnostics => _stderr.toString().trim();

  @override
  Future<void> send(JsonMap message) async {
    if (_closed) throw StateError('Claude Code transport is closed.');
    _process.stdin.writeln(jsonEncode(message));
    await _process.stdin.flush();
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _process.stdin.close().timeout(const Duration(seconds: 1));
    } on Object {
      // The process tree is terminated below.
    }
    await terminateProcessTree(_process);
    await _process.exitCode;
  }

  static JsonMap _decodeMessage(String line) {
    final decoded = jsonDecode(line);
    if (decoded is! Map) {
      throw const FormatException('Claude Code emitted non-object JSON.');
    }
    return decoded.cast<String, Object?>();
  }
}

enum ClaudeCodeErrorKind {
  unavailable,
  authentication,
  rateLimited,
  timeout,
  processExited,
  protocol,
  turnFailed,
}

final class ClaudeCodeException implements Exception {
  const ClaudeCodeException(this.kind, this.message);

  final ClaudeCodeErrorKind kind;
  final String message;

  @override
  String toString() => message;
}

/// Whether the local Claude Code CLI can be offered, and which login it uses.
final class ClaudeCodeAvailability {
  const ClaudeCodeAvailability.available({
    this.authSource = claudeCodeSubscriptionAuthSource,
  }) : available = true,
       reason = null;

  const ClaudeCodeAvailability.unavailable(String this.reason)
    : available = false,
      authSource = null;

  final bool available;
  final String? authSource;
  final String? reason;

  /// Reads `claude auth status` with the same filtered environment as runs.
  ///
  /// A logged-in status does not prove the cached token still works; model
  /// access is checked when a run starts.
  static Future<ClaudeCodeAvailability> probe({
    String executable = 'claude',
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      final result = await Process.run(
        executable,
        const ['auth', 'status', '--json'],
        runInShell: false,
        includeParentEnvironment: false,
        environment: claudeCodeProcessEnvironment(),
      ).timeout(timeout);
      return fromAuthStatus(result.exitCode, result.stdout.toString());
    } on ProcessException {
      return const ClaudeCodeAvailability.unavailable(
        'Claude Code CLI is not installed.',
      );
    } on TimeoutException {
      return const ClaudeCodeAvailability.unavailable(
        'Claude Code auth status timed out.',
      );
    }
  }

  static ClaudeCodeAvailability fromAuthStatus(int exitCode, String stdout) {
    Object? status;
    try {
      status = jsonDecode(stdout);
    } on FormatException {
      status = null;
    }
    if (exitCode != 0 || status is! Map || status['loggedIn'] != true) {
      return const ClaudeCodeAvailability.unavailable(
        'Claude Code is not authenticated; run `claude auth login`.',
      );
    }
    final method = status['authMethod'];
    return ClaudeCodeAvailability.available(
      authSource: method == 'claude.ai' || method == null
          ? claudeCodeSubscriptionAuthSource
          : 'local Claude Code ${SafeMetadata.identifier(method.toString())}',
    );
  }
}

/// Runs Dextero tools through the local Claude Code CLI.
///
/// Claude Code's built-in tools are disabled. Dextero's tools are offered as
/// an in-process MCP server over the CLI's stream-json control protocol, and
/// every permission prompt is answered by Dextero, so the CLI cannot widen
/// Dextero's tool or approval policy. Authentication stays with the CLI.
final class ClaudeCodeConversationAgent
    implements ConversationAgent, ApprovalAwareConversationAgent {
  ClaudeCodeConversationAgent({
    required List<Tool> tools,
    this.model,
    this.workingDirectory,
    this.authSource = claudeCodeSubscriptionAuthSource,
    Set<String> approvalRequiredTools = defaultApprovalRequiredTools,
    this.messageTimeout = const Duration(minutes: 5),
    String claudeExecutable = 'claude',
    ClaudeCodeTransportFactory? transportFactory,
    String? sessionId,
  }) : _tools = {for (final tool in tools) tool.definition.name: tool},
       approvalRequiredTools = Set.unmodifiable(approvalRequiredTools),
       _sessionId = sessionId ?? _uuidV4(),
       _transportFactory =
           transportFactory ??
           ((arguments) => ProcessClaudeCodeTransport.start(
             arguments,
             executable: claudeExecutable,
             workingDirectory: workingDirectory,
           )) {
    if (_tools.length != tools.length) {
      throw ArgumentError('Tool names must be unique.');
    }
  }

  final String? model;
  final String? workingDirectory;
  final String authSource;
  final Set<String> approvalRequiredTools;
  final Duration messageTimeout;
  final Map<String, Tool> _tools;
  final ClaudeCodeTransportFactory _transportFactory;

  /// One Claude Code session per Dextero conversation; later runs resume it.
  final String _sessionId;
  var _sessionStarted = false;
  var _requestCounter = 0;

  String get sessionId => _sessionId;

  List<String> get _arguments => [
    '--print',
    '--input-format',
    'stream-json',
    '--output-format',
    'stream-json',
    '--verbose',
    '--include-partial-messages',
    if (model != null) ...['--model', model!],
    '--tools',
    '',
    '--strict-mcp-config',
    '--mcp-config',
    jsonEncode({
      'mcpServers': {
        claudeCodeToolServer: {'type': 'sdk', 'name': claudeCodeToolServer},
      },
    }),
    '--permission-prompt-tool',
    'stdio',
    '--setting-sources',
    '',
    '--safe-mode',
    '--disable-slash-commands',
    '--no-chrome',
    '--append-system-prompt',
    'Use the Dextero MCP tools for all file and command operations. '
        'Use run_command for normal CLI execution. Use run_shell only when '
        'shell syntax is required.',
    if (_sessionStarted) ...[
      '--resume',
      _sessionId,
    ] else ...[
      '--session-id',
      _sessionId,
    ],
  ];

  @override
  Future<ConversationAgentResult> run(
    String prompt, {
    required ConversationAgentEventSink onEvent,
    required CancellationToken cancellationToken,
  }) => runWithApproval(
    prompt,
    onEvent: onEvent,
    cancellationToken: cancellationToken,
  );

  @override
  Future<ConversationAgentResult> runWithApproval(
    String prompt, {
    required ConversationAgentEventSink onEvent,
    required CancellationToken cancellationToken,
    ToolApprovalRequester? onApprovalRequest,
  }) async {
    if (prompt.trim().isEmpty) {
      throw ArgumentError.value(prompt, 'prompt', 'must not be empty');
    }
    cancellationToken.throwIfCancellationRequested();
    final ClaudeCodeTransport transport;
    try {
      transport = await _transportFactory(_arguments);
    } on ProcessException catch (error) {
      throw ClaudeCodeException(
        ClaudeCodeErrorKind.unavailable,
        'Claude Code CLI could not start: ${error.message}',
      );
    }
    final turn = _Turn(
      agent: this,
      transport: transport,
      onEvent: onEvent,
      cancellationToken: cancellationToken,
      onApprovalRequest: onApprovalRequest,
    );
    try {
      return ConversationAgentResult(output: await turn.run(prompt));
    } on RunCancelledException {
      await turn.interrupt();
      rethrow;
    } finally {
      await turn.close();
    }
  }

  String _nextRequestId() => 'dextero-${++_requestCounter}';

  static String _uuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}

/// State for one CLI invocation answering one user prompt.
final class _Turn {
  _Turn({
    required this.agent,
    required this.transport,
    required this.onEvent,
    required this.cancellationToken,
    required this.onApprovalRequest,
  }) : _messages = StreamIterator(transport.messages);

  final ClaudeCodeConversationAgent agent;
  final ClaudeCodeTransport transport;
  final ConversationAgentEventSink onEvent;
  final CancellationToken cancellationToken;
  final ToolApprovalRequester? onApprovalRequest;
  final StreamIterator<JsonMap> _messages;

  final _startedToolCalls = <String>{};
  final _completedToolCalls = <String>{};

  /// Gated tool-use IDs approved through Dextero, with the approved input.
  final _approvedInputs = <String, String>{};

  Future<String> run(String prompt) async {
    final initializeId = agent._nextRequestId();
    await transport.send({
      'type': 'control_request',
      'request_id': initializeId,
      'request': {
        'subtype': 'initialize',
        'sdkMcpServers': [claudeCodeToolServer],
      },
    });
    await transport.send({
      'type': 'user',
      'message': {'role': 'user', 'content': prompt},
      'parent_tool_use_id': null,
      'session_id': agent.sessionId,
    });

    while (await _moveNext()) {
      final message = _messages.current;
      switch (message['type']) {
        case 'control_request':
          await _handleControlRequest(message);
        case 'control_response':
          final response = message['response'];
          if (response is Map &&
              response['request_id'] == initializeId &&
              response['subtype'] == 'error') {
            throw ClaudeCodeException(
              ClaudeCodeErrorKind.protocol,
              'Claude Code rejected initialization: '
              '${SafeMetadata.text(response['error']).text}',
            );
          }
        case 'system' when message['subtype'] == 'init':
          agent._sessionStarted = true;
          final model = message['model'] is String
              ? message['model']! as String
              : agent.model ?? 'default';
          await _emit(
            ConversationAgentEventKind.lifecycle,
            SafeMetadata.text(
              'Claude Code is working · $model · ${agent.authSource}',
            ),
          );
        case 'stream_event' when message['parent_tool_use_id'] == null:
          final event = message['event'];
          final delta = event is Map ? event['delta'] : null;
          if (delta is Map &&
              delta['type'] == 'text_delta' &&
              delta['text'] is String &&
              (delta['text']! as String).isNotEmpty) {
            await _emit(
              ConversationAgentEventKind.assistantDelta,
              SafeMetadata.message(delta['text']! as String),
            );
          }
        case 'assistant':
          await _recordToolUses(message['message']);
        case 'result':
          return _finish(message);
      }
    }
    final diagnostics = transport.diagnostics;
    throw ClaudeCodeException(
      ClaudeCodeErrorKind.processExited,
      diagnostics.isEmpty
          ? 'Claude Code exited before the turn completed.'
          : 'Claude Code exited before the turn completed: '
                '${SafeMetadata.text(diagnostics).text}',
    );
  }

  /// Asks the CLI to stop the turn; closing the process follows regardless.
  Future<void> interrupt() async {
    try {
      await transport
          .send({
            'type': 'control_request',
            'request_id': agent._nextRequestId(),
            'request': {'subtype': 'interrupt'},
          })
          .timeout(const Duration(seconds: 1));
    } on Object {
      // The transport may already be gone.
    }
  }

  Future<void> close() async {
    await _messages.cancel();
    await transport.close();
  }

  Future<bool> _moveNext() async {
    cancellationToken.throwIfCancellationRequested();
    final moveNext = _messages.moveNext().timeout(
      agent.messageTimeout,
      onTimeout: () => throw ClaudeCodeException(
        ClaudeCodeErrorKind.timeout,
        'Claude Code produced no output for '
        '${agent.messageTimeout.inSeconds} seconds.',
      ),
    );
    return cancellationToken.waitFor(moveNext);
  }

  String _finish(JsonMap result) {
    final text = result['result'];
    if (result['is_error'] == true || result['subtype'] != 'success') {
      final status = result['api_error_status'];
      final detail = text is String && text.trim().isNotEmpty
          ? text
          : result['errors'] is List && (result['errors']! as List).isNotEmpty
          ? (result['errors']! as List).join('; ')
          : 'turn ended with ${result['subtype'] ?? 'an unknown status'}';
      throw switch (status) {
        401 || 403 => const ClaudeCodeException(
          ClaudeCodeErrorKind.authentication,
          'Claude Code authentication failed; run `claude auth login`.',
        ),
        429 => ClaudeCodeException(
          ClaudeCodeErrorKind.rateLimited,
          'Claude Code is rate limited: ${SafeMetadata.text(detail).text}',
        ),
        _ => ClaudeCodeException(
          ClaudeCodeErrorKind.turnFailed,
          'Claude Code failed: ${SafeMetadata.text(detail).text}',
        ),
      };
    }
    if (text is! String || text.trim().isEmpty) {
      throw const ClaudeCodeException(
        ClaudeCodeErrorKind.turnFailed,
        'Claude Code completed without a final message.',
      );
    }
    return text;
  }

  Future<void> _emit(
    ConversationAgentEventKind kind,
    SafeSummary summary, {
    String? toolCallId,
    String? toolName,
    bool? success,
  }) async => onEvent(
    ConversationAgentEvent(
      kind: kind,
      summary: summary,
      toolCallId: toolCallId,
      toolName: toolName,
      success: success,
    ),
  );

  Future<void> _recordToolUses(Object? message) async {
    final content = message is Map ? message['content'] : null;
    if (content is! List) return;
    for (final block in content.whereType<Map>()) {
      if (block['type'] != 'tool_use' || block['id'] is! String) continue;
      await _started(
        block['id']! as String,
        _toolName(block['name']),
        block['input'] is Map
            ? (block['input']! as Map).cast<String, Object?>()
            : const {},
      );
    }
  }

  Future<void> _started(String id, String name, JsonMap input) async {
    if (!_startedToolCalls.add(id)) return;
    await _emit(
      ConversationAgentEventKind.toolCallStarted,
      SafeMetadata.toolCall(name, input),
      toolCallId: id,
      toolName: name,
    );
  }

  Future<void> _completed(
    String id,
    String name,
    Object? content, {
    required bool success,
  }) async {
    if (!_completedToolCalls.add(id)) return;
    await _emit(
      ConversationAgentEventKind.toolCallCompleted,
      SafeMetadata.toolResult(name, content, success: success),
      toolCallId: id,
      toolName: name,
      success: success,
    );
  }

  Future<void> _handleControlRequest(JsonMap message) async {
    final requestId = message['request_id'];
    final request = message['request'];
    if (request is! Map) {
      await _respondError(requestId, 'Malformed control request.');
      return;
    }
    switch (request['subtype']) {
      case 'can_use_tool':
        await _respond(requestId, await _permission(request));
      case 'mcp_message' when request['server_name'] == claudeCodeToolServer:
        final mcpResponse = await _mcp(request['message']);
        await _respond(requestId, {'mcp_response': mcpResponse});
      default:
        await _respondError(
          requestId,
          'Dextero does not support ${request['subtype']} requests.',
        );
    }
  }

  /// Every Claude Code permission prompt is decided by Dextero's policy.
  Future<JsonMap> _permission(Map request) async {
    final rawName = request['tool_name']?.toString() ?? 'unknown_tool';
    final toolUseId =
        request['tool_use_id']?.toString() ?? agent._nextRequestId();
    final input = request['input'] is Map
        ? snapshotJsonMap((request['input']! as Map).cast<String, Object?>())
        : const <String, Object?>{};
    final name = _toolName(rawName);
    await _started(toolUseId, name, input);
    if (!rawName.startsWith(_toolPrefix) || !agent._tools.containsKey(name)) {
      const reason = 'Dextero only permits its own harness tools.';
      await _completed(toolUseId, name, reason, success: false);
      return {'behavior': 'deny', 'message': reason};
    }
    if (agent.approvalRequiredTools.contains(name)) {
      final denial = await _approve(toolUseId, name, input);
      if (denial != null) {
        await _completed(toolUseId, name, denial, success: false);
        return {'behavior': 'deny', 'message': denial};
      }
      _approvedInputs[toolUseId] = jsonEncode(input);
    }
    return {'behavior': 'allow', 'updatedInput': input};
  }

  /// Returns a denial reason, or null once Dextero approval is granted.
  Future<String?> _approve(String toolUseId, String name, JsonMap input) async {
    final requester = onApprovalRequest;
    if (requester == null) return 'Approval is unavailable for $name.';
    final approved = await cancellationToken.waitFor(
      requester(
        ToolApprovalRequest(
          toolCallId: toolUseId,
          toolName: name,
          summary: SafeMetadata.approvalRequest(name, input),
        ),
      ),
    );
    cancellationToken.throwIfCancellationRequested();
    return approved ? null : '$name was not approved.';
  }

  Future<JsonMap> _mcp(Object? rawMessage) async {
    if (rawMessage is! Map) {
      return _rpcError(null, -32600, 'Malformed MCP message.');
    }
    final id = rawMessage['id'];
    final params = rawMessage['params'];
    switch (rawMessage['method']) {
      case 'initialize':
        return _rpcResult(id, {
          'protocolVersion': params is Map
              ? params['protocolVersion']
              : '2025-06-18',
          'capabilities': {'tools': <String, Object?>{}},
          'serverInfo': {'name': claudeCodeToolServer, 'version': '0.0.1'},
        });
      case 'tools/list':
        return _rpcResult(id, {
          'tools': [
            for (final tool in agent._tools.values)
              {
                'name': tool.definition.name,
                'description': tool.definition.description,
                'inputSchema': tool.definition.inputSchema,
              },
          ],
        });
      case 'tools/call':
        return _rpcResult(id, await _callTool(params));
      case 'ping':
        return _rpcResult(id, const {});
      case final String method when method.startsWith('notifications/'):
        return _rpcResult(id, const {});
      default:
        return _rpcError(id, -32601, 'Method not found.');
    }
  }

  Future<JsonMap> _callTool(Object? params) async {
    final name = params is Map && params['name'] is String
        ? params['name']! as String
        : 'unknown_tool';
    final meta = params is Map ? params['_meta'] : null;
    final toolUseId = meta is Map && meta['claudecode/toolUseId'] is String
        ? meta['claudecode/toolUseId']! as String
        : agent._nextRequestId();
    final rawArguments = params is Map ? params['arguments'] : null;
    final arguments = rawArguments is Map
        ? snapshotJsonMap(rawArguments.cast<String, Object?>())
        : const <String, Object?>{};
    await _started(toolUseId, name, arguments);

    Object? content;
    var success = false;
    final tool = agent._tools[name];
    if (tool == null) {
      content = 'Unknown tool: $name';
    } else if (rawArguments is! Map) {
      content = 'Tool arguments must be a JSON object.';
    } else {
      // Approval is normally granted in can_use_tool; enforce it here too in
      // case a CLI setting skipped the prompt or the input changed.
      String? denial;
      if (agent.approvalRequiredTools.contains(name) &&
          _approvedInputs.remove(toolUseId) != jsonEncode(arguments)) {
        denial = await _approve(toolUseId, name, arguments);
      }
      if (denial != null) {
        content = denial;
      } else {
        try {
          content = await tool.call(
            arguments,
            cancellationToken: cancellationToken,
            onOutput: (update) => _emit(
              ConversationAgentEventKind.toolOutput,
              SafeMetadata.text(
                '$name ${update.stream}: ${update.byteCount} bytes',
              ),
              toolCallId: toolUseId,
              toolName: name,
            ),
          );
          cancellationToken.throwIfCancellationRequested();
          success = true;
        } on RunCancelledException {
          rethrow;
        } on Object catch (error) {
          cancellationToken.throwIfCancellationRequested();
          content = error.toString();
        }
      }
    }
    await _completed(toolUseId, name, content, success: success);
    return {
      'content': [
        {'type': 'text', 'text': _encodeToolContent(content)},
      ],
      'isError': !success,
    };
  }

  Future<void> _respond(Object? requestId, JsonMap response) => transport.send({
    'type': 'control_response',
    'response': {
      'subtype': 'success',
      'request_id': requestId,
      'response': response,
    },
  });

  Future<void> _respondError(Object? requestId, String error) => transport.send(
    {
      'type': 'control_response',
      'response': {'subtype': 'error', 'request_id': requestId, 'error': error},
    },
  );

  static JsonMap _rpcResult(Object? id, JsonMap result) => {
    'jsonrpc': '2.0',
    'id': ?id,
    'result': result,
  };

  static JsonMap _rpcError(Object? id, int code, String message) => {
    'jsonrpc': '2.0',
    'id': ?id,
    'error': {'code': code, 'message': message},
  };

  static String _toolName(Object? rawName) {
    final name = rawName?.toString() ?? 'unknown_tool';
    return name.startsWith(_toolPrefix)
        ? name.substring(_toolPrefix.length)
        : name;
  }

  static String _encodeToolContent(Object? content) {
    if (content is String) return content;
    try {
      return jsonEncode(content);
    } on JsonUnsupportedObjectError {
      return content.toString();
    }
  }
}
