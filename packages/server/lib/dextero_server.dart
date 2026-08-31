import 'dart:io';

import 'package:dextero_core/dextero_core.dart';
import 'package:serverpod/serverpod.dart';

import 'src/auth/dextero_token_authenticator.dart';
import 'src/control/chat_runtime.dart';
import 'src/generated/endpoints.dart';
import 'src/generated/protocol.dart';

export 'src/control/chat_runtime.dart' show ChatRuntime;

/// Starts the database-free local control plane.
Future<void> run(List<String> arguments) async {
  final token = Platform.environment['DEXTERO_CONTROL_TOKEN'];
  if (token == null || token.length < 32) {
    throw StateError(
      'DEXTERO_CONTROL_TOKEN must contain at least 32 characters. '
      'Generate one before starting the server.',
    );
  }

  final workspace = Directory(
    Platform.environment['DEXTERO_WORKSPACE'] ?? Directory.current.path,
  ).absolute.path;
  final store = InMemoryChatHistoryStore();
  final service = ChatService(
    store: store,
    agent: CodexConversationAgent(
      agent: CodexAppServerAgent(workingDirectory: workspace),
      tools: [
        ListFilesTool(root: workspace),
        ReadFileTool(root: workspace),
        EditFileTool(root: workspace),
        RunCommandTool(workingDirectory: workspace),
        RunShellTool(workingDirectory: workspace),
      ],
    ),
  );
  final conversation = await service.createConversation();
  await startControlServer(
    arguments: arguments,
    token: token,
    chatService: service,
    defaultConversationId: conversation.id,
  );
}

/// Starts the typed control server around an injected chat service.
///
/// The injection seam is used by the network acceptance test as well as the
/// production bootstrap, so both exercise the same endpoint stack.
Future<Serverpod> startControlServer({
  required String token,
  required ChatService chatService,
  required String defaultConversationId,
  List<String> arguments = const [],
  int? apiPort,
  bool runInGuardedZone = true,
}) async {
  if (token.length < 32) {
    throw ArgumentError.value(
      token.length,
      'token',
      'must contain at least 32 characters',
    );
  }
  ChatRuntime.configure(
    chatService: chatService,
    defaultConversationId: defaultConversationId,
  );
  final config = apiPort == null
      ? null
      : ServerpodConfig.defaultConfig().copyWith(
          apiServer: ServerConfig(
            port: apiPort,
            publicHost: 'localhost',
            publicPort: apiPort,
            publicScheme: 'http',
          ),
        );
  final pod = Serverpod(
    arguments,
    Protocol(),
    Endpoints(),
    config: config,
    authenticationHandler: DexteroTokenAuthenticator(token).authenticate,
  );
  await pod.start(runInGuardedZone: runInGuardedZone);
  return pod;
}
