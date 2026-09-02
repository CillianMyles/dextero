import 'agent.dart';
import 'cancellation.dart';
import 'chat_service.dart';
import 'model.dart';
import 'safe_metadata.dart';
import 'tool.dart';

/// Adapts any provider-neutral [AgentModel] to Dextero's conversation runtime.
final class ModelConversationAgent implements ConversationAgent {
  ModelConversationAgent({
    required AgentModel model,
    required List<Tool> tools,
    required this.providerName,
    this.maxTurns = 12,
  }) : _model = model,
       _tools = List.unmodifiable(tools);

  final AgentModel _model;
  final List<Tool> _tools;
  final String providerName;
  final int maxTurns;

  @override
  Future<ConversationAgentResult> run(
    String prompt, {
    required ConversationAgentEventSink onEvent,
    required CancellationToken cancellationToken,
  }) async {
    await onEvent(
      ConversationAgentEvent(
        kind: ConversationAgentEventKind.lifecycle,
        summary: SafeMetadata.text('$providerName is working'),
      ),
    );
    final result =
        await AgentLoop(model: _model, tools: _tools, maxTurns: maxTurns).run(
          prompt,
          cancellationToken: cancellationToken,
          onActivity: (activity) => onEvent(
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
          ),
        );
    return ConversationAgentResult(output: result.output);
  }
}
