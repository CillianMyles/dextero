import 'package:dextero_server/dextero_client.dart';

final class TerminalRenderer {
  const TerminalRenderer();

  String plainEntryLine(ChatEntry entry) {
    final label = switch (entry.kind) {
      ChatEntryKind.userMessage => 'you',
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

  String safeText(String value) => value
      .replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '')
      .replaceAll(
        RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F]'),
        '',
      );
}
