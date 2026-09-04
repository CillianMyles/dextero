import 'dart:io';

import '../opened_file_identity.dart';
import '../workspace_boundary.dart';

final class WorkspacePath {
  WorkspacePath(
    String root, {
    WorkspaceBoundary? boundary,
    Future<void> Function(String path)? beforeFileOpen,
  }) : _beforeFileOpen = beforeFileOpen,
       _root = Directory(root).absolute,
       _boundary = boundary {
    if (boundary != null && _root.path != boundary.root) {
      throw ArgumentError('workspace boundary must match the configured root');
    }
  }

  final Directory _root;
  final WorkspaceBoundary? _boundary;
  final Future<void> Function(String path)? _beforeFileOpen;

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

    await _boundary?.validate();
    final rootPath = _boundary?.root ?? await _root.resolveSymbolicLinks();
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

  Future<RandomAccessFile> openExistingFile(
    String relativePath, {
    FileMode mode = FileMode.read,
  }) async {
    final path = await resolveExisting(
      relativePath,
      expectedType: FileSystemEntityType.file,
    );
    final openedIdentity = await OpenedFileIdentity.capturePath(path);
    try {
      await _beforeFileOpen?.call(path);
      final file = await File(path).open(mode: mode);
      try {
        await openedIdentity.verify(file);
        await _boundary?.validate();
        return file;
      } on Object {
        await file.close();
        rethrow;
      }
    } finally {
      openedIdentity.close();
    }
  }

  Future<String> canonicalRoot() async {
    await _boundary?.validate();
    final boundary = _boundary;
    if (boundary != null) return boundary.root;
    return _root.resolveSymbolicLinks();
  }

  Future<void> validateBoundary() async => _boundary?.validate();
}
