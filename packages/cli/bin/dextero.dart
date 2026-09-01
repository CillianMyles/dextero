import 'dart:io';

import 'package:dextero_cli/dextero_cli.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await run(arguments);
}

Future<int> run(List<String> arguments) async {
  const io = SystemTerminalIo();
  final token = Platform.environment['DEXTERO_CONTROL_TOKEN'];
  if (token == null || token.length < 32) {
    io.error(
      'DEXTERO_CONTROL_TOKEN is missing. Run the client with `make cli`.',
    );
    return 64;
  }

  final rawUrl =
      Platform.environment['DEXTERO_CONTROL_URL'] ?? 'http://localhost:8080/';
  final jsonl = arguments.isNotEmpty && arguments.first == '--jsonl';
  final effectiveArguments = jsonl ? arguments.skip(1).toList() : arguments;
  final chat = TerminalChat(
    client: ServerpodTerminalChatClient(serverUrl: rawUrl, token: token),
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
