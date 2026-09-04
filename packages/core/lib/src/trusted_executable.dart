import 'dart:io';

/// Resolves a fixed executable outside the directory controlled by the agent.
Future<String> resolveTrustedExecutable(
  Directory controlledDirectory,
  List<String> candidates,
) async {
  final controlledPath = await controlledDirectory.resolveSymbolicLinks();
  for (final candidate in candidates) {
    final file = File(candidate);
    if (!file.isAbsolute || !await file.exists()) continue;
    final resolved = await file.resolveSymbolicLinks();
    if (!_inside(resolved, controlledPath)) return resolved;
  }
  throw FileSystemException(
    'Cannot locate a trusted executable outside the controlled workspace',
    controlledDirectory.path,
  );
}

String? operatingSystemEnvironmentValue(String name) {
  for (final entry in Platform.environment.entries) {
    if (entry.key.toUpperCase() == name) return entry.value;
  }
  return null;
}

bool _inside(String path, String directory) {
  if (Platform.isWindows) {
    path = path.toLowerCase();
    directory = directory.toLowerCase();
  }
  return path == directory ||
      path.startsWith('$directory${Platform.pathSeparator}');
}
