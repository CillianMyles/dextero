import 'claude_code_agent.dart';
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

enum AgentProvider { codex, gemini, claude }

const defaultCodexModel = 'default';
const codexSparkModel = 'gpt-5.3-codex-spark';
const claudeOpusModel = 'opus';
const claudeSonnetModel = 'sonnet';

/// A provider-qualified choice; model names alone are not globally unique.
final class AgentModelOption {
  const AgentModelOption({
    required this.provider,
    required this.modelName,
    String? authSource,
  }) : _authSource = authSource;

  final AgentProvider provider;
  final String modelName;
  final String? _authSource;

  /// Where the credentials for this choice come from, for display only.
  String get authSource =>
      _authSource ??
      switch (provider) {
        AgentProvider.gemini => 'Gemini API key',
        AgentProvider.codex => 'local Codex CLI login',
        AgentProvider.claude => claudeCodeSubscriptionAuthSource,
      };

  String get id => '${provider.name}:$modelName';
  String get label => switch (provider) {
    AgentProvider.gemini => 'Gemini · $modelName',
    AgentProvider.codex => 'Codex · $modelName',
    AgentProvider.claude => 'Claude · $modelName',
  };
  String get toolDescription => switch (provider) {
    AgentProvider.gemini => 'Dextero harness tools',
    AgentProvider.codex => 'Codex tools + Dextero harness tools',
    AgentProvider.claude => 'Dextero harness tools via Claude Code',
  };
}

/// Resolves the production conversation agent from explicit environment data.
final class AgentRuntimeConfiguration {
  AgentRuntimeConfiguration._({
    required this.provider,
    required this.modelName,
    required this.availableModels,
    required this.availableOptions,
    required String? apiKey,
    required String claudeAuthSource,
  }) : _apiKey = apiKey,
       _claudeAuthSource = claudeAuthSource;

  /// [claudeCode] is the probed CLI state; Claude is offered only when it is
  /// available, mirroring how Gemini requires a configured key.
  factory AgentRuntimeConfiguration.fromEnvironment(
    Map<String, String> environment, {
    ClaudeCodeAvailability claudeCode =
        const ClaudeCodeAvailability.unavailable(
          'Claude Code availability was not checked.',
        ),
  }) {
    final apiKey = _nonEmpty(environment['GEMINI_API_KEY']);
    final requestedProvider = _nonEmpty(
      environment['DEXTERO_MODEL_PROVIDER'],
    )?.toLowerCase();
    final provider = switch (requestedProvider) {
      null => apiKey == null ? AgentProvider.codex : AgentProvider.gemini,
      'codex' => AgentProvider.codex,
      'gemini' => AgentProvider.gemini,
      'claude' => AgentProvider.claude,
      _ => throw ArgumentError.value(
        requestedProvider,
        'DEXTERO_MODEL_PROVIDER',
        'must be codex, gemini, or claude',
      ),
    };
    if (provider == AgentProvider.gemini && apiKey == null) {
      throw StateError(
        'GEMINI_API_KEY is required when DEXTERO_MODEL_PROVIDER=gemini.',
      );
    }
    if (provider == AgentProvider.claude && !claudeCode.available) {
      throw StateError(
        'DEXTERO_MODEL_PROVIDER=claude requires Claude Code: '
        '${claudeCode.reason}',
      );
    }
    final codexModel = _nonEmpty(environment['DEXTERO_CODEX_MODEL']);
    final geminiModel =
        _nonEmpty(environment['DEXTERO_GEMINI_MODEL']) ?? defaultGeminiModel;
    final claudeModel =
        _nonEmpty(environment['DEXTERO_CLAUDE_MODEL']) ?? claudeOpusModel;
    final modelName = switch (provider) {
      AgentProvider.gemini => geminiModel,
      AgentProvider.codex => codexModel ?? codexSparkModel,
      AgentProvider.claude => claudeModel,
    };
    final codexModels = _availableModels(
      environment['DEXTERO_CODEX_MODELS'],
      fallback: const [codexSparkModel, defaultCodexModel],
      selected: codexModel ?? codexSparkModel,
    );
    final geminiModels = _availableModels(
      environment['DEXTERO_GEMINI_MODELS'],
      fallback: const [defaultGeminiModel],
      selected: geminiModel,
    );
    final claudeModels = _availableModels(
      environment['DEXTERO_CLAUDE_MODELS'],
      fallback: const [claudeOpusModel, claudeSonnetModel],
      selected: claudeModel,
    );
    final claudeAuthSource =
        claudeCode.authSource ?? claudeCodeSubscriptionAuthSource;
    final availableOptions = <AgentModelOption>[
      if (apiKey != null)
        for (final model in geminiModels)
          AgentModelOption(provider: AgentProvider.gemini, modelName: model),
      for (final model in codexModels)
        AgentModelOption(provider: AgentProvider.codex, modelName: model),
      if (claudeCode.available)
        for (final model in claudeModels)
          AgentModelOption(
            provider: AgentProvider.claude,
            modelName: model,
            authSource: claudeAuthSource,
          ),
    ];
    return AgentRuntimeConfiguration._(
      provider: provider,
      modelName: modelName,
      availableModels: switch (provider) {
        AgentProvider.gemini => geminiModels,
        AgentProvider.codex => codexModels,
        AgentProvider.claude => claudeModels,
      },
      availableOptions: List.unmodifiable(availableOptions),
      apiKey: apiKey,
      claudeAuthSource: claudeAuthSource,
    );
  }

  final AgentProvider provider;
  final String modelName;
  final List<String> availableModels;
  final List<AgentModelOption> availableOptions;

  String get selectedModelId => '${provider.name}:$modelName';
  final String? _apiKey;
  final String _claudeAuthSource;

  String get providerName => provider.name;

  ConversationAgent createAgent({
    required String workspace,
    String? modelName,
    AgentProvider? provider,
    GeminiTransport? geminiTransport,
    CodexTransportFactory? codexTransportFactory,
    ClaudeCodeTransportFactory? claudeTransportFactory,
  }) {
    final selectedProvider = provider ?? this.provider;
    final selectedModel = modelName ?? this.modelName;
    if (!availableOptions.any(
      (option) =>
          option.provider == selectedProvider &&
          option.modelName == selectedModel,
    )) {
      throw ArgumentError.value(
        selectedModel,
        'modelName',
        'must be an advertised provider/model combination',
      );
    }
    final tools = <Tool>[
      ListFilesTool(root: workspace),
      ReadFileTool(root: workspace),
      EditFileTool(root: workspace),
      RunCommandTool(workingDirectory: workspace),
      RunShellTool(workingDirectory: workspace),
    ];
    return switch (selectedProvider) {
      AgentProvider.codex => CodexConversationAgent(
        agent: CodexAppServerAgent(
          model: selectedModel == defaultCodexModel ? null : selectedModel,
          workingDirectory: workspace,
          transportFactory: codexTransportFactory,
        ),
        tools: tools,
        approvalRequiredTools: const {'edit_file'},
      ),
      AgentProvider.gemini => ModelConversationAgent(
        model: GeminiModel(
          model: selectedModel,
          transport: geminiTransport ?? GeminiHttpTransport(apiKey: _apiKey!),
        ),
        tools: tools,
        providerName: 'Gemini',
        approvalRequiredTools: const {'edit_file'},
      ),
      AgentProvider.claude => ClaudeCodeConversationAgent(
        model: selectedModel,
        workingDirectory: workspace,
        authSource: _claudeAuthSource,
        tools: tools,
        approvalRequiredTools: const {'edit_file'},
        transportFactory: claudeTransportFactory,
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
    final normalizedConfigured = _nonEmpty(configured);
    final values = normalizedConfigured == null
        ? fallback
        : normalizedConfigured.split(',').map((value) => value.trim());
    final models = <String>[];
    for (final value in values) {
      if (value.isNotEmpty && !models.contains(value)) models.add(value);
    }
    if (!models.contains(selected)) models.insert(0, selected);
    return List.unmodifiable(models);
  }
}
