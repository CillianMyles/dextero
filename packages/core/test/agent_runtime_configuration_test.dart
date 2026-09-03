import 'package:dextero_core/dextero_core.dart';
import 'package:test/test.dart';

void main() {
  test('uses Codex when no provider credentials are configured', () {
    final configuration = AgentRuntimeConfiguration.fromEnvironment(const {});

    expect(configuration.provider, AgentProvider.codex);
    expect(configuration.providerName, 'codex');
    expect(configuration.modelName, defaultCodexModel);
    expect(configuration.availableModels, [defaultCodexModel, codexSparkModel]);
  });

  test('uses default model choices when Make exports an empty list', () {
    final configuration = AgentRuntimeConfiguration.fromEnvironment(const {
      'DEXTERO_CODEX_MODELS': '',
    });

    expect(configuration.availableModels, [defaultCodexModel, codexSparkModel]);
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
