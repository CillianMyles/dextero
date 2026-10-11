import 'protocol/protocol.dart';

/// What the host-side agent is doing, derived from ordered history so every
/// surface (app, terminal, or a later paired speaker) shows the same state.
enum AgentActivity { idle, thinking, acting, awaitingApproval }

final class AgentActivityState {
  const AgentActivityState(this.activity, {this.runId, this.toolName});

  static const idle = AgentActivityState(AgentActivity.idle);

  final AgentActivity activity;
  final String? runId;

  /// The tool being used or awaiting approval, when known.
  final String? toolName;
}

const _terminalStatuses = {
  ChatEntryStatus.completed,
  ChatEntryStatus.failed,
  ChatEntryStatus.cancelled,
};

bool isTerminalRunEntry(ChatEntry entry) =>
    entry.kind == ChatEntryKind.lifecycle &&
    _terminalStatuses.contains(entry.status);

/// Derives the latest unfinished run's activity from [entries] in sequence
/// order. Runs without a terminal lifecycle entry are considered active.
AgentActivityState agentActivityOf(Iterable<ChatEntry> entries) {
  final ordered = entries.toList()
    ..sort((left, right) => left.sequence.compareTo(right.sequence));
  final finished = {
    for (final entry in ordered)
      if (entry.runId != null && isTerminalRunEntry(entry)) entry.runId,
  };
  final runId = ordered.reversed
      .map((entry) => entry.runId)
      .firstWhere(
        (runId) => runId != null && !finished.contains(runId),
        orElse: () => null,
      );
  if (runId == null) return AgentActivityState.idle;

  final pendingApprovals = <String, String?>{};
  final openTools = <String, String?>{};
  for (final entry in ordered.where((entry) => entry.runId == runId)) {
    final approvalId = entry.approvalId;
    final toolCallId = entry.toolCallId;
    if (entry.kind == ChatEntryKind.approval && approvalId != null) {
      if (entry.status == ChatEntryStatus.pending) {
        pendingApprovals[approvalId] = entry.toolName;
      } else {
        pendingApprovals.remove(approvalId);
      }
    } else if (toolCallId != null) {
      if (entry.kind == ChatEntryKind.toolResult) {
        openTools.remove(toolCallId);
      } else if (entry.kind == ChatEntryKind.toolCall ||
          entry.kind == ChatEntryKind.toolOutput) {
        openTools[toolCallId] = entry.toolName;
      }
    }
  }
  if (pendingApprovals.isNotEmpty) {
    return AgentActivityState(
      AgentActivity.awaitingApproval,
      runId: runId,
      toolName: pendingApprovals.values.last,
    );
  }
  if (openTools.isNotEmpty) {
    return AgentActivityState(
      AgentActivity.acting,
      runId: runId,
      toolName: openTools.values.last,
    );
  }
  return AgentActivityState(AgentActivity.thinking, runId: runId);
}
