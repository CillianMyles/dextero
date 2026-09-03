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

const defaultCodexModel = 'default';
const codexSparkModel = 'gpt-5.3-codex-spark';

/// Resolves the production conversation agent from explicit environment data.
final class AgentRuntimeConfiguration {
  AgentRuntimeConfiguration._({
    required this.provider,
    required this.modelName,
    required this.availableModels,
    required String? apiKey,
  }) : _apiKey = apiKey;

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
    final modelName = provider == AgentProvider.gemini
        ? geminiModel
        : codexModel ?? defaultCodexModel;
    final availableModels = _availableModels(
      environment[provider == AgentProvider.codex
          ? 'DEXTERO_CODEX_MODELS'
          : 'DEXTERO_GEMINI_MODELS'],
      fallback: provider == AgentProvider.codex
          ? const [defaultCodexModel, codexSparkModel]
          : [defaultGeminiModel],
      selected: modelName,
    );
    return AgentRuntimeConfiguration._(
      provider: provider,
      modelName: modelName,
      availableModels: availableModels,
      apiKey: apiKey,
    );
  }

  final AgentProvider provider;
  final String modelName;
  final List<String> availableModels;
  final String? _apiKey;

  String get providerName => provider.name;

  ConversationAgent createAgent({
    required String workspace,
    String? modelName,
    GeminiTransport? geminiTransport,
  }) {
    final selectedModel = modelName ?? this.modelName;
    if (!availableModels.contains(selectedModel)) {
      throw ArgumentError.value(
        selectedModel,
        'modelName',
        'must be one of ${availableModels.join(', ')}',
      );
    }
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
          model: selectedModel == defaultCodexModel ? null : selectedModel,
          workingDirectory: workspace,
        ),
        tools: tools,
      ),
      AgentProvider.gemini => ModelConversationAgent(
        model: GeminiModel(
          model: selectedModel,
          transport: geminiTransport ?? GeminiHttpTransport(apiKey: _apiKey!),
        ),
        tools: tools,
        providerName: 'Gemini',
      ),
    };
  }

  static String? _nonEmpty(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static List<String> _availableModels(
    String? configured, {
    required List<String> fallback,
    required String selected,
  }) {
    final values = configured == null
        ? fallback
        : configured.split(',').map((value) => value.trim());
    final models = <String>[];
    for (final value in values) {
      if (value.isNotEmpty && !models.contains(value)) models.add(value);
    }
    if (!models.contains(selected)) models.insert(0, selected);
    return List.unmodifiable(models);
  }
}
