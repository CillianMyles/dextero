import 'package:dextero_server/dextero_client.dart';

final class TerminalRenderer {
  const TerminalRenderer();

  String plainEntryLine(ChatEntry entry) {
    final label = switch (entry.kind) {
      ChatEntryKind.userMessage =>
        entry.modality == ChatModality.voice ? 'you · voice' : 'you',
      ChatEntryKind.assistantMessage => 'dextero',
      ChatEntryKind.assistantDelta => 'model output',
      ChatEntryKind.toolCall ||
      ChatEntryKind.toolOutput ||
      ChatEntryKind.toolResult => entry.toolName ?? entry.kind.name,
      ChatEntryKind.approval => 'approval',
      ChatEntryKind.lifecycle => entry.status.name,
      ChatEntryKind.error => 'error',
    };
    return '[${safeText(label)}] ${entryContent(entry)}';
  }

  String entryContent(ChatEntry entry) {
    final content = safeText(entry.content);
    if (entry.transcriptionEngine case final engine?
        when entry.modality == ChatModality.voice) {
      return '$content\n(transcribed by ${safeText(engine)})';
    }
    if (entry.kind != ChatEntryKind.approval ||
        entry.status != ChatEntryStatus.pending ||
        entry.runId == null ||
        entry.approvalId == null) {
      return content;
    }
    final runId = safeText(entry.runId!);
    final approvalId = safeText(entry.approvalId!);
    final truncationWarning = entry.truncated
        ? 'WARNING: Approval preview truncated; part of the proposed edit is not shown.\n'
        : '';
    return '$content\n'
        '$truncationWarning'
        'Run ID: $runId\n'
        'Approval ID: $approvalId\n'
        'Approve: make approve RUN_ID=$runId APPROVAL_ID=$approvalId';
  }

  /// One status line describing what the agent is doing.
  String activityNotice(AgentActivityState state) {
    final tool = state.toolName == null ? null : safeText(state.toolName!);
    return switch (state.activity) {
      AgentActivity.idle => 'Ready',
      AgentActivity.thinking => 'Dextero is thinking…',
      AgentActivity.acting => 'Dextero is using ${tool ?? 'a tool'}…',
      AgentActivity.awaitingApproval =>
        'Waiting for approval${tool == null ? '' : ' of $tool'}; '
            'use the approve command shown above',
    };
  }

  String safeText(String value) => value
      .replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '')
      .replaceAll(
        RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F]'),
        '',
      );
}
