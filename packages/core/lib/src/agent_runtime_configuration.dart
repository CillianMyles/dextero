import 'codex_app_server_agent.dart';
import 'chat_service.dart';
import 'gemini_model.dart';
import 'model_conversation_agent.dart';
import 'tool.dart';
import 'tools/edit_file_tool.dart';
import 'tools/list_files_tool.dart';
import 'tools/read_file_tool.dart';
import 'tools/run_command_tool.dart';
import 'tools/run_shell_tool.dart';

enum AgentProvider { codex, gemini }

/// Resolves the production conversation agent from explicit environment data.
final class AgentRuntimeConfiguration {
  AgentRuntimeConfiguration._({
    required this.provider,
    required this.modelName,
    required String? apiKey,
    required String? codexModel,
  }) : _apiKey = apiKey,
       _codexModel = codexModel;

  factory AgentRuntimeConfiguration.fromEnvironment(
    Map<String, String> environment,
  ) {
    final apiKey = _nonEmpty(environment['GEMINI_API_KEY']);
    final requestedProvider = _nonEmpty(
      environment['DEXTERO_MODEL_PROVIDER'],
    )?.toLowerCase();
    final provider = switch (requestedProvider) {
      null => apiKey == null ? AgentProvider.codex : AgentProvider.gemini,
      'codex' => AgentProvider.codex,
      'gemini' => AgentProvider.gemini,
      _ => throw ArgumentError.value(
        requestedProvider,
        'DEXTERO_MODEL_PROVIDER',
        'must be codex or gemini',
      ),
    };
    if (provider == AgentProvider.gemini && apiKey == null) {
      throw StateError(
        'GEMINI_API_KEY is required when DEXTERO_MODEL_PROVIDER=gemini.',
      );
    }
    final codexModel = _nonEmpty(environment['DEXTERO_CODEX_MODEL']);
    final geminiModel =
        _nonEmpty(environment['DEXTERO_GEMINI_MODEL']) ?? defaultGeminiModel;
    return AgentRuntimeConfiguration._(
      provider: provider,
      modelName: provider == AgentProvider.gemini
          ? geminiModel
          : codexModel ?? 'default',
      apiKey: apiKey,
      codexModel: codexModel,
    );
  }

  final AgentProvider provider;
  final String modelName;
  final String? _apiKey;
  final String? _codexModel;

  String get providerName => provider.name;

  ConversationAgent createAgent({
    required String workspace,
    GeminiTransport? geminiTransport,
  }) {
    final tools = <Tool>[
      ListFilesTool(root: workspace),
      ReadFileTool(root: workspace),
      EditFileTool(root: workspace),
      RunCommandTool(workingDirectory: workspace),
      RunShellTool(workingDirectory: workspace),
    ];
    return switch (provider) {
      AgentProvider.codex => CodexConversationAgent(
        agent: CodexAppServerAgent(
          model: _codexModel,
          workingDirectory: workspace,
        ),
        tools: tools,
        approvalRequiredTools: const {'edit_file'},
      ),
      AgentProvider.gemini => ModelConversationAgent(
        model: GeminiModel(
          model: modelName,
          transport: geminiTransport ?? GeminiHttpTransport(apiKey: _apiKey!),
        ),
        tools: tools,
        providerName: 'Gemini',
        approvalRequiredTools: const {'edit_file'},
      ),
    };
  }

  static String? _nonEmpty(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
