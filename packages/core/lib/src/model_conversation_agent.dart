import 'agent.dart';
import 'approval.dart';
import 'cancellation.dart';
import 'chat_history.dart';
import 'chat_service.dart';
import 'model.dart';
import 'safe_metadata.dart';
import 'tool.dart';

typedef ModelCostEstimator = int? Function(ModelUsage usage);

/// Adapts any provider-neutral [AgentModel] to Dextero's conversation runtime.
final class ModelConversationAgent
    implements ConversationAgent, ApprovalAwareConversationAgent {
  ModelConversationAgent({
    required AgentModel model,
    required List<Tool> tools,
    required this.providerName,
    this.modelName,
    this.authSource,
    ModelCostEstimator? estimateCost,
    Set<String> approvalRequiredTools = defaultApprovalRequiredTools,
    this.maxTurns = 12,
  }) : _model = model,
       _tools = List.unmodifiable(tools),
       _estimateCost = estimateCost,
       approvalRequiredTools = Set.unmodifiable(approvalRequiredTools);

  /// Streamed text is coalesced into history entries of about this size.
  static const deltaFlushCharacters = 1200;

  final AgentModel _model;
  final List<Tool> _tools;
  final ModelCostEstimator? _estimateCost;
  final String providerName;

  /// Model and credential source recorded with each run's usage receipt.
  final String? modelName;
  final String? authSource;
  final Set<String> approvalRequiredTools;
  final int maxTurns;

  @override
  Future<ConversationAgentResult> run(
    String prompt, {
    required ConversationAgentEventSink onEvent,
    required CancellationToken cancellationToken,
  }) => runWithApproval(
    prompt,
    onEvent: onEvent,
    cancellationToken: cancellationToken,
  );

  @override
  Future<ConversationAgentResult> runWithApproval(
    String prompt, {
    required ConversationAgentEventSink onEvent,
    required CancellationToken cancellationToken,
    ToolApprovalRequester? onApprovalRequest,
  }) async {
    await onEvent(
      ConversationAgentEvent(
        kind: ConversationAgentEventKind.lifecycle,
        summary: SafeMetadata.text('$providerName is working'),
      ),
    );
    var usage = ModelUsage.zero;
    var modelRequests = 0;
    final pendingText = StringBuffer();

    Future<void> flushText() async {
      if (pendingText.toString().trim().isEmpty) {
        pendingText.clear();
        return;
      }
      final text = pendingText.toString();
      pendingText.clear();
      await onEvent(
        ConversationAgentEvent(
          kind: ConversationAgentEventKind.assistantDelta,
          summary: SafeMetadata.message(text),
        ),
      );
    }

    Future<void> recordUsage() async {
      if (modelRequests == 0) return;
      final receipt = ChatRunUsage(
        provider: providerName,
        model: modelName ?? 'unknown',
        authSource: authSource ?? 'unknown',
        inputTokens: usage.inputTokens,
        outputTokens: usage.outputTokens,
        cacheCreationInputTokens: usage.cacheCreationInputTokens,
        cacheReadInputTokens: usage.cacheReadInputTokens,
        modelRequests: modelRequests,
        costMicrosUsd: _estimateCost?.call(usage),
      );
      await onEvent(
        ConversationAgentEvent(
          kind: ConversationAgentEventKind.usage,
          summary: SafeMetadata.text(describeRunUsage(receipt)),
          usage: receipt,
        ),
      );
    }

    final AgentRun result;
    try {
      result =
          await AgentLoop(
            model: _model,
            tools: _tools,
            approvalRequiredTools: approvalRequiredTools,
            maxTurns: maxTurns,
          ).run(
            prompt,
            cancellationToken: cancellationToken,
            onApprovalRequest: onApprovalRequest,
            onUsage: (turnUsage) {
              usage += turnUsage;
              modelRequests++;
            },
            onModelEvent: (event) async {
              switch (event) {
                case ModelTextDelta(:final text):
                  pendingText.write(text);
                  if (pendingText.length >= deltaFlushCharacters ||
                      text.contains('\n\n')) {
                    await flushText();
                  }
                case ModelRetryScheduled(
                  :final reason,
                  :final delay,
                  :final attempt,
                ):
                  await flushText();
                  await onEvent(
                    ConversationAgentEvent(
                      kind: ConversationAgentEventKind.error,
                      summary: SafeMetadata.text(
                        '$reason Retrying in ${delay.inSeconds}s '
                        '(retry $attempt).',
                      ),
                      retrying: true,
                    ),
                  );
              }
            },
            onActivity: (activity) async {
              await flushText();
              await onEvent(
                ConversationAgentEvent(
                  kind: switch (activity.kind) {
                    AgentLoopActivityKind.toolCallStarted =>
                      ConversationAgentEventKind.toolCallStarted,
                    AgentLoopActivityKind.toolOutput =>
                      ConversationAgentEventKind.toolOutput,
                    AgentLoopActivityKind.toolCallCompleted =>
                      ConversationAgentEventKind.toolCallCompleted,
                  },
                  summary: activity.summary,
                  toolCallId: activity.toolCallId,
                  toolName: activity.toolName,
                  success: activity.success,
                ),
              );
            },
          );
    } on RunCancelledException {
      rethrow;
    } on Object {
      if (!cancellationToken.isCancellationRequested) {
        await flushText();
        await recordUsage();
      }
      rethrow;
    }
    await flushText();
    await recordUsage();
    return ConversationAgentResult(output: result.output);
  }
}

/// A one-line receipt shared by history and both clients.
String describeRunUsage(ChatRunUsage usage) {
  final cost = usage.costMicrosUsd;
  final cached = usage.cacheReadInputTokens + usage.cacheCreationInputTokens;
  return [
    usage.provider,
    usage.model,
    usage.authSource,
    '${_count(usage.inputTokens + cached)} input'
        '${cached == 0 ? '' : ' (${_count(usage.cacheReadInputTokens)} cache '
                  'read, ${_count(usage.cacheCreationInputTokens)} cache write)'}',
    '${_count(usage.outputTokens)} output',
    cost == null ? 'cost unavailable' : formatMicrosUsd(cost),
  ].join(' · ');
}

/// Formats micro-dollars with enough precision for small runs.
String formatMicrosUsd(int micros) {
  final dollars = micros / 1000000;
  return '\$${dollars.toStringAsFixed(dollars >= 1 ? 2 : 4)}';
}

String _count(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) buffer.write(',');
    buffer.write(digits[index]);
  }
  return buffer.toString();
}
