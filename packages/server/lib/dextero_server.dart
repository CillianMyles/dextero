import 'dart:io';

import 'package:dextero_core/dextero_core.dart';
import 'package:serverpod/serverpod.dart';

import 'src/auth/dextero_token_authenticator.dart';
import 'src/control/chat_runtime.dart';
import 'src/generated/endpoints.dart';
import 'src/generated/protocol.dart';

export 'src/control/chat_runtime.dart' show ChatRuntime, ModelSelector;
export 'src/control/agent_runtime_configuration.dart'
    show
        AgentProvider,
        AgentRuntimeConfiguration,
        codexSparkModel,
        defaultCodexModel;

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
  final bindAddress = _parseBindAddress(
    Platform.environment['DEXTERO_BIND_ADDRESS'] ?? '127.0.0.1',
  );
  final agentConfiguration = AgentRuntimeConfiguration.fromEnvironment(
    Platform.environment,
  );
  final store = InMemoryChatHistoryStore();
  final service = ChatService(
    store: store,
    agent: agentConfiguration.createAgent(workspace: workspace),
  );
  final conversation = await service.createConversation();
  await startControlServer(
    arguments: arguments,
    token: token,
    chatService: service,
    defaultConversationId: conversation.id,
    modelProvider: agentConfiguration.providerName,
    modelName: agentConfiguration.modelName,
    bindAddress: bindAddress,
    availableModels: agentConfiguration.availableModels,
    modelSelector: (modelName) => service.selectAgent(
      conversationId: conversation.id,
      agent: agentConfiguration.createAgent(
        workspace: workspace,
        modelName: modelName,
      ),
    ),
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
  String modelProvider = 'codex',
  String modelName = 'default',
  InternetAddress? bindAddress,
  List<String>? availableModels,
  ModelSelector? modelSelector,
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
    modelProvider: modelProvider,
    modelName: modelName,
    availableModels: availableModels,
    modelSelector: modelSelector,
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
  final effectiveBindAddress = bindAddress ?? InternetAddress.loopbackIPv4;
  await IOOverrides.runWithIOOverrides(
    () => pod.start(runInGuardedZone: runInGuardedZone),
    _ServerBindOverrides(effectiveBindAddress),
  );
  return pod;
}

InternetAddress _parseBindAddress(String value) {
  final normalized = value.trim();
  final address = InternetAddress.tryParse(normalized);
  if (address == null) {
    throw ArgumentError.value(
      value,
      'DEXTERO_BIND_ADDRESS',
      'must be an IPv4 or IPv6 address',
    );
  }
  return address;
}

/// Constrains Serverpod 3's internal `anyIPv6` listener to an explicit address.
final class _ServerBindOverrides extends IOOverrides {
  _ServerBindOverrides(this.address);

  final InternetAddress address;

  @override
  Future<ServerSocket> serverSocketBind(
    dynamic ignoredAddress,
    int port, {
    int backlog = 0,
    bool v6Only = false,
    bool shared = false,
  }) => super.serverSocketBind(
    address,
    port,
    backlog: backlog,
    v6Only: address.type == InternetAddressType.IPv6 && v6Only,
    shared: shared,
  );
}
