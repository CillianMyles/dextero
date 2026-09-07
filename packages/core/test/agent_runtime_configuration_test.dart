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
}
