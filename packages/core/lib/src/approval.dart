import 'safe_metadata.dart';

/// Tools that require one-shot approval unless a caller supplies another
/// explicit policy.
const Set<String> defaultApprovalRequiredTools = {'edit_file'};

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
