import 'dart:io';

import 'package:path/path.dart' as paths;

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

/// Returns absolute executable candidates from the host's search path.
List<String> operatingSystemExecutableCandidates(
  String executable, {
  Map<String, String>? environment,
}) {
  final values = environment ?? Platform.environment;
  String? searchPath;
  String? pathExtensions;
  for (final entry in values.entries) {
    if (entry.key.toUpperCase() == 'PATH') searchPath = entry.value;
    if (entry.key.toUpperCase() == 'PATHEXT') pathExtensions = entry.value;
  }
  if (searchPath == null) return const [];
  final extensions = Platform.isWindows
      ? (pathExtensions ?? '.COM;.EXE;.BAT;.CMD')
            .split(';')
            .where((value) => value.isNotEmpty)
      : const [''];
  return [
    for (var directory in searchPath.split(Platform.isWindows ? ';' : ':'))
      if (paths.isAbsolute(directory = _unquote(directory.trim())))
        for (final extension in extensions)
          paths.join(
            directory,
            Platform.isWindows &&
                    !executable.toLowerCase().endsWith(extension.toLowerCase())
                ? '$executable$extension'
                : executable,
          ),
  ];
}

String _unquote(String value) {
  if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
    return value.substring(1, value.length - 1);
  }
  return value;
}

bool _inside(String path, String directory) {
  if (Platform.isWindows) {
    path = path.toLowerCase();
    directory = directory.toLowerCase();
  }
  return path == directory ||
      path.startsWith('$directory${Platform.pathSeparator}');
}
