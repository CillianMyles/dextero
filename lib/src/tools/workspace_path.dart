import 'dart:io';

final class WorkspacePath {
  WorkspacePath(String root) : _root = Directory(root).absolute;

  final Directory _root;

  String get root => _root.path;

  Future<String> resolveExisting(
    String relativePath, {
    required FileSystemEntityType expectedType,
    bool allowRoot = false,
  }) async {
    if (relativePath.isEmpty) {
      throw const FormatException('path must be a non-empty string');
    }
    if (File(relativePath).isAbsolute) {
      throw ArgumentError('path must be relative to the configured workspace');
    }

    final rootPath = await _root.resolveSymbolicLinks();
    final candidate = File('$rootPath${Platform.pathSeparator}$relativePath');
    final resolvedPath = await candidate.resolveSymbolicLinks();
    final insideRoot =
        resolvedPath == rootPath ||
        resolvedPath.startsWith('$rootPath${Platform.pathSeparator}');
    if (!insideRoot || (!allowRoot && resolvedPath == rootPath)) {
      throw ArgumentError('path escapes the configured workspace');
    }

    final actualType = await FileSystemEntity.type(resolvedPath);
    if (actualType != expectedType) {
      final expected = switch (expectedType) {
        FileSystemEntityType.file => 'file',
        FileSystemEntityType.directory => 'directory',
        _ => expectedType.toString(),
      };
      throw ArgumentError('path must reference a $expected');
    }
    return resolvedPath;
  }

  Future<String> canonicalRoot() => _root.resolveSymbolicLinks();
}
