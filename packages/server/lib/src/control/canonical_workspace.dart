import 'dart:io';

/// Resolves the workspace once so identity and agents use the same target.
Future<String> canonicalWorkspacePath(String workspace) async {
  final directory = Directory(workspace).absolute;
  if (!await directory.exists()) {
    throw ArgumentError.value(
      workspace,
      'workspace',
      'must be an existing directory',
    );
  }
  return directory.resolveSymbolicLinks();
}
