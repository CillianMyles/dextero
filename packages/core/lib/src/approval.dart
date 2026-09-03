import 'safe_metadata.dart';

/// A concrete tool action that must be approved before it can execute.
final class ToolApprovalRequest {
  const ToolApprovalRequest({
    required this.toolCallId,
    required this.toolName,
    required this.summary,
  });

  final String toolCallId;
  final String toolName;
  final SafeSummary summary;
}

typedef ToolApprovalRequester =
    Future<bool> Function(ToolApprovalRequest request);
