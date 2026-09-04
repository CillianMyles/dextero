import 'agent.dart';
import 'approval.dart';
import 'cancellation.dart';
import 'chat_service.dart';
import 'model.dart';
import 'safe_metadata.dart';
import 'tool.dart';

/// Adapts any provider-neutral [AgentModel] to Dextero's conversation runtime.
final class ModelConversationAgent
    implements ConversationAgent, ApprovalAwareConversationAgent {
  ModelConversationAgent({
    required AgentModel model,
    required List<Tool> tools,
    required this.providerName,
    Set<String> approvalRequiredTools = defaultApprovalRequiredTools,
    this.maxTurns = 12,
  }) : _model = model,
       _tools = List.unmodifiable(tools),
       approvalRequiredTools = Set.unmodifiable(approvalRequiredTools);

  final AgentModel _model;
  final List<Tool> _tools;
  final String providerName;
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
    final result =
        await AgentLoop(
          model: _model,
          tools: _tools,
          approvalRequiredTools: approvalRequiredTools,
          maxTurns: maxTurns,
        ).run(
          prompt,
          cancellationToken: cancellationToken,
          onApprovalRequest: onApprovalRequest,
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
