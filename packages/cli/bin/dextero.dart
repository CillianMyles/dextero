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
  final chat = TerminalChat(
    client: ServerpodTerminalChatClient(serverUrl: rawUrl, token: token),
    io: io,
  );
  return chat.run(
    initialMessage: arguments.isEmpty ? null : arguments.join(' '),
  );
}
