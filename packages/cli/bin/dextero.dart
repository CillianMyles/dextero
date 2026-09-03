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

typedef TuiRunner = Future<int> Function({required TerminalChatClient client});

TerminalChatClient _createClient({
  required String serverUrl,
  required String token,
}) => ServerpodTerminalChatClient(serverUrl: serverUrl, token: token);

Future<int> _runTui({required TerminalChatClient client}) =>
    runNoctermChat(client: client);

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
  final jsonl = arguments.isNotEmpty && arguments.first == '--jsonl';
  final effectiveArguments = jsonl ? arguments.skip(1).toList() : arguments;
  final client = clientFactory(serverUrl: rawUrl, token: token);
  if (io.hasInputTerminal &&
      io.hasOutputTerminal &&
      !jsonl &&
      effectiveArguments.isEmpty) {
    return tuiRunner(client: client);
  }
  final chat = TerminalChat(
    client: client,
    io: io,
    outputMode: jsonl ? TerminalOutputMode.jsonl : TerminalOutputMode.human,
  );
  if (effectiveArguments case ['--cancel', final runId]) {
    return chat.run(cancelRunId: runId);
  }
  if (effectiveArguments.isNotEmpty && effectiveArguments.first == '--cancel') {
    io.error('Usage: dextero --cancel <run-id>');
    return 64;
  }
  return chat.run(
    initialMessage: effectiveArguments.isEmpty
        ? null
        : effectiveArguments.join(' '),
  );
}
