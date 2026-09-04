import 'package:dextero_core/dextero_core.dart';

/// Resolves the workspace once so identity and agents use the same target.
Future<WorkspaceBoundary> canonicalWorkspaceBoundary(String workspace) =>
    WorkspaceBoundary.capture(workspace);
