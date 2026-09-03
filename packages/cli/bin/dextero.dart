import 'dart:io';

import 'package:dextero_cli/dextero_cli.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await run(arguments);
}

typedef TerminalClientFactory =
    TerminalChatClient Function({
      required String serverUrl,
      required String token,
    });

typedef TuiRunner =
    Future<int> Function({
      required TerminalChatClient client,
      String? modelName,
    });

TerminalChatClient _createClient({
  required String serverUrl,
  required String token,
}) => ServerpodTerminalChatClient(serverUrl: serverUrl, token: token);

Future<int> _runTui({required TerminalChatClient client, String? modelName}) =>
    runNoctermChat(client: client, modelName: modelName);

Future<int> run(
  List<String> arguments, {
  TerminalIo io = const SystemTerminalIo(),
  Map<String, String>? environment,
  TerminalClientFactory clientFactory = _createClient,
  TuiRunner tuiRunner = _runTui,
}) async {
  final effectiveEnvironment = environment ?? Platform.environment;
  final token = effectiveEnvironment['DEXTERO_CONTROL_TOKEN'];
  if (token == null || token.length < 32) {
    io.error(
      'DEXTERO_CONTROL_TOKEN is missing. Run the client with `make cli`.',
    );
    return 64;
  }

  final rawUrl =
      effectiveEnvironment['DEXTERO_CONTROL_URL'] ?? 'http://localhost:8080/';
  var jsonl = false;
  String? modelName;
  String? cancelRunId;
  final message = <String>[];
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    switch (argument) {
      case '--jsonl':
        jsonl = true;
      case '--model':
        if (index + 1 >= arguments.length) {
          io.error('Usage: dextero [--jsonl] [--model <name>] [message]');
          return 64;
        }
        modelName = arguments[++index];
      case '--cancel':
        if (index + 1 >= arguments.length) {
          io.error('Usage: dextero --cancel <run-id>');
          return 64;
        }
        cancelRunId = arguments[++index];
      default:
        message.add(argument);
    }
  }
  if (cancelRunId != null && message.isNotEmpty) {
    io.error('A cancellation request cannot include a message.');
    return 64;
  }
  if (cancelRunId != null && modelName != null) {
    io.error('A cancellation request cannot select a model.');
    return 64;
  }
  final client = clientFactory(serverUrl: rawUrl, token: token);
  if (io.hasInputTerminal &&
      io.hasOutputTerminal &&
      !jsonl &&
      message.isEmpty &&
      cancelRunId == null) {
    return tuiRunner(client: client, modelName: modelName);
  }
  final chat = TerminalChat(
    client: client,
    io: io,
    outputMode: jsonl ? TerminalOutputMode.jsonl : TerminalOutputMode.human,
  );
  return chat.run(
    initialMessage: message.isEmpty ? null : message.join(' '),
    cancelRunId: cancelRunId,
    modelName: modelName,
  );
}
