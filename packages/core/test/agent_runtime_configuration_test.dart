import 'package:dextero_core/dextero_core.dart';
import 'package:test/test.dart';

void main() {
  test(
    'advertises both providers in priority order and creates either agent',
    () {
      final configuration = AgentRuntimeConfiguration.fromEnvironment(const {
        'GEMINI_API_KEY': 'test-key',
      });
      expect(configuration.selectedModelId, 'gemini:gemini-2.5-flash');
      expect(configuration.availableOptions.map((option) => option.id), [
        'gemini:gemini-2.5-flash',
        'codex:gpt-5.3-codex-spark',
        'codex:default',
      ]);
      for (final option in configuration.availableOptions) {
        final agent = configuration.createAgent(
          workspace: '.',
          provider: option.provider,
          modelName: option.modelName,
        );
        expect(
          agent,
          option.provider == AgentProvider.gemini
              ? isA<ModelConversationAgent>()
              : isA<CodexConversationAgent>(),
        );
      }
      expect(
        () => configuration.createAgent(
          workspace: '.',
          provider: AgentProvider.gemini,
          modelName: codexSparkModel,
        ),
        throwsArgumentError,
      );
    },
  );

  test('an initial provider override keeps the other provider selectable', () {
    final configuration = AgentRuntimeConfiguration.fromEnvironment(const {
      'DEXTERO_MODEL_PROVIDER': 'codex',
      'GEMINI_API_KEY': 'test-key',
    });
    expect(configuration.provider, AgentProvider.codex);
    expect(configuration.availableOptions.first.provider, AgentProvider.gemini);
  });

  test('does not advertise or instantiate Gemini without credentials', () {
    final configuration = AgentRuntimeConfiguration.fromEnvironment(const {});
    expect(configuration.availableOptions.map((option) => option.id), [
      'codex:gpt-5.3-codex-spark',
      'codex:default',
    ]);
    expect(
      () => configuration.createAgent(
        workspace: '.',
        provider: AgentProvider.gemini,
        modelName: defaultGeminiModel,
      ),
      throwsArgumentError,
    );
  });

  test('uses Codex when no provider credentials are configured', () {
    final configuration = AgentRuntimeConfiguration.fromEnvironment(const {});

    expect(configuration.provider, AgentProvider.codex);
    expect(configuration.providerName, 'codex');
    expect(configuration.modelName, codexSparkModel);
    expect(configuration.availableModels, [codexSparkModel, defaultCodexModel]);
  });

  test('uses default model choices when Make exports an empty list', () {
    final configuration = AgentRuntimeConfiguration.fromEnvironment(const {
      'DEXTERO_CODEX_MODELS': '',
    });

    expect(configuration.availableModels, [codexSparkModel, defaultCodexModel]);
  });

  test('selects Gemini when an API key is plugged in', () {
    final configuration = AgentRuntimeConfiguration.fromEnvironment(const {
      'GEMINI_API_KEY': 'secret-key',
    });

    expect(configuration.provider, AgentProvider.gemini);
    expect(configuration.providerName, 'gemini');
    expect(configuration.modelName, defaultGeminiModel);
  });

  test('explicit Codex selection wins when a Gemini key exists', () {
    final configuration = AgentRuntimeConfiguration.fromEnvironment(const {
      'DEXTERO_MODEL_PROVIDER': 'codex',
      'GEMINI_API_KEY': 'ignored-by-codex',
      'DEXTERO_CODEX_MODEL': 'codex-custom',
    });

    expect(configuration.provider, AgentProvider.codex);
    expect(configuration.modelName, 'codex-custom');
  });

  test('supports an explicit Gemini model override', () {
    final configuration = AgentRuntimeConfiguration.fromEnvironment(const {
      'DEXTERO_MODEL_PROVIDER': ' gemini ',
      'GEMINI_API_KEY': 'secret-key',
      'DEXTERO_GEMINI_MODEL': 'gemini-custom',
      'DEXTERO_GEMINI_MODELS': 'gemini-fast, gemini-custom, gemini-fast',
    });

    expect(configuration.provider, AgentProvider.gemini);
    expect(configuration.modelName, 'gemini-custom');
    expect(configuration.availableModels, ['gemini-fast', 'gemini-custom']);
  });

  test('adds a selected model to a configured allowlist', () {
    final configuration = AgentRuntimeConfiguration.fromEnvironment(const {
      'DEXTERO_CODEX_MODEL': 'codex-custom',
      'DEXTERO_CODEX_MODELS': 'default,gpt-5.3-codex-spark',
    });

    expect(configuration.availableModels, [
      'codex-custom',
      defaultCodexModel,
      codexSparkModel,
    ]);
    expect(
      () => configuration.createAgent(workspace: '.', modelName: 'not-allowed'),
      throwsArgumentError,
    );
  });

  test('rejects explicit Gemini selection without an API key', () {
    expect(
      () => AgentRuntimeConfiguration.fromEnvironment(const {
        'DEXTERO_MODEL_PROVIDER': 'gemini',
      }),
      throwsStateError,
    );
  });

  test('rejects an unknown provider', () {
    expect(
      () => AgentRuntimeConfiguration.fromEnvironment(const {
        'DEXTERO_MODEL_PROVIDER': 'other',
      }),
      throwsArgumentError,
    );
  });

  test('offers Claude after the other providers when Claude Code is ready', () {
    final configuration = AgentRuntimeConfiguration.fromEnvironment(const {
      'GEMINI_API_KEY': 'test-key',
    }, claudeCode: const ClaudeCodeAvailability.available());
    expect(configuration.selectedModelId, 'gemini:gemini-2.5-flash');
    expect(configuration.availableOptions.map((option) => option.id), [
      'gemini:gemini-2.5-flash',
      'codex:gpt-5.3-codex-spark',
      'codex:default',
      'claude:opus',
      'claude:sonnet',
    ]);
    final claude = configuration.availableOptions.last;
    expect(claude.label, 'Claude · sonnet');
    expect(claude.authSource, 'local Claude Code subscription');
    expect(claude.toolDescription, 'Dextero harness tools via Claude Code');
    expect(
      configuration.createAgent(
        workspace: '.',
        provider: AgentProvider.claude,
        modelName: claudeOpusModel,
      ),
      isA<ClaudeCodeConversationAgent>()
          .having((agent) => agent.model, 'model', 'opus')
          .having(
            (agent) => agent.authSource,
            'authSource',
            'local Claude Code subscription',
          ),
    );
  });

  test('does not advertise Claude when Claude Code is unavailable', () {
    final configuration = AgentRuntimeConfiguration.fromEnvironment(const {});
    expect(
      configuration.availableOptions.map((option) => option.provider),
      isNot(contains(AgentProvider.claude)),
    );
  });

  test('selects a configured Claude model as the initial choice', () {
    final configuration = AgentRuntimeConfiguration.fromEnvironment(const {
      'DEXTERO_MODEL_PROVIDER': 'claude',
      'DEXTERO_CLAUDE_MODEL': 'claude-opus-5-5',
      'DEXTERO_CLAUDE_MODELS': 'opus',
    }, claudeCode: const ClaudeCodeAvailability.available());
    expect(configuration.selectedModelId, 'claude:claude-opus-5-5');
    expect(configuration.availableModels, ['claude-opus-5-5', 'opus']);
  });

  test('rejects explicit Claude selection when Claude Code is unavailable', () {
    expect(
      () => AgentRuntimeConfiguration.fromEnvironment(
        const {'DEXTERO_MODEL_PROVIDER': 'claude'},
        claudeCode: const ClaudeCodeAvailability.unavailable(
          'Claude Code CLI is not installed.',
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('not installed'),
        ),
      ),
    );
  });
}
