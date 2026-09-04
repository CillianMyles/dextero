import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as paths;

import 'chat_history.dart';
import 'filesystem_identity.dart';
import 'process_environment.dart';

/// Stable identity of the local host, project, and selected workspace.
final class HostIdentity {
  HostIdentity({
    required String deviceId,
    required String projectId,
    required String projectName,
    required String workspaceId,
    required String workspaceName,
  }) : deviceId = _validateId(deviceId, 'device'),
       projectId = _validateId(projectId, 'project'),
       projectName = _validateName(projectName, 'projectName'),
       workspaceId = _validateId(workspaceId, 'workspace'),
       workspaceName = _validateName(workspaceName, 'workspaceName');

  final String deviceId;
  final String projectId;
  final String projectName;
  final String workspaceId;
  final String workspaceName;
}

/// Resolves stable local identities without coupling them to chat persistence.
///
/// The registry intentionally lives outside a controlled workspace. A project
/// key is shared by Git worktrees, while a workspace key identifies the exact
/// checkout or non-Git directory selected by the host.
final class LocalIdentityRegistry {
  LocalIdentityRegistry({
    required File stateFile,
    IdentifierGenerator? identifiers,
  }) : _stateFile = stateFile,
       _identifiers = identifiers ?? SecureIdentifierGenerator();

  factory LocalIdentityRegistry.fromEnvironment(Map<String, String> values) {
    final configured = values['DEXTERO_STATE_DIRECTORY']?.trim();
    final directory = configured == null || configured.isEmpty
        ? _defaultStateDirectory(values)
        : Directory(configured).absolute;
    return LocalIdentityRegistry(
      stateFile: File(_join(directory.path, 'identity-registry-v1.json')),
    );
  }

  final File _stateFile;
  final IdentifierGenerator _identifiers;
  static final Map<String, Future<void>> _inProcessTails = {};

  File get stateFile => _stateFile;

  Future<HostIdentity> resolve(String workspace) async {
    final workspaceDirectory = Directory(workspace).absolute;
    if (!await workspaceDirectory.exists()) {
      throw ArgumentError.value(
        workspace,
        'workspace',
        'must be an existing directory',
      );
    }
    final workspacePath = await workspaceDirectory.resolveSymbolicLinks();
    final project = await _findProject(Directory(workspacePath));
    return _withInProcessLock(_stateFile.absolute.path, () async {
      await _stateFile.parent.create(recursive: true);
      final lock = await File(
        '${_stateFile.path}.lock',
      ).open(mode: FileMode.append);
      var locked = false;
      try {
        await lock.lock(FileLock.blockingExclusive);
        locked = true;
        // Re-read after taking the lock so concurrent hosts merge their entries.
        final state = await _readState();
        final projectKey = await _projectKey(project);
        final checkoutKey = await _checkoutKey(project, projectKey);
        final checkoutOwner = checkoutKey == null
            ? null
            : await resolveFilesystemIdentity(project.root);
        final registeredOwner = checkoutKey == null
            ? null
            : state.checkoutOwners[checkoutKey];
        if (registeredOwner != null && registeredOwner != checkoutOwner) {
          throw FormatException(
            'Git checkout metadata is already associated with another '
            'workspace.',
          );
        }
        final workspaceKey = checkoutKey == null
            ? projectKey
            : '$checkoutKey::${await resolveFilesystemIdentity(Directory(workspacePath))}';
        final deviceId = state.deviceId ?? _identifiers.next('device');
        final projectId =
            state.projects[projectKey] ?? _identifiers.next('project');
        final workspaceId =
            state.workspaces[workspaceKey] ?? _identifiers.next('workspace');
        final changed =
            state.deviceId != deviceId ||
            state.projects[projectKey] != projectId ||
            state.workspaces[workspaceKey] != workspaceId ||
            (checkoutKey != null && registeredOwner == null);

        if (changed) {
          await _writeState(
            _IdentityState(
              deviceId: deviceId,
              projects: {...state.projects, projectKey: projectId},
              workspaces: {...state.workspaces, workspaceKey: workspaceId},
              checkoutOwners: {
                ...state.checkoutOwners,
                ?checkoutKey: checkoutOwner!,
              },
            ),
          );
        }

        return HostIdentity(
          deviceId: deviceId,
          projectId: projectId,
          projectName: _filesystemDisplayName(project.root.path),
          workspaceId: workspaceId,
          workspaceName: _filesystemDisplayName(workspacePath),
        );
      } finally {
        if (locked) await lock.unlock();
        await lock.close();
      }
    });
  }

  Future<_IdentityState> _readState() async {
    if (!await _stateFile.exists()) return const _IdentityState();
    try {
      final decoded = jsonDecode(await _stateFile.readAsString());
      if (decoded is! Map<String, Object?> || decoded['version'] != 1) {
        throw const FormatException('unsupported identity registry version');
      }
      return _IdentityState(
        deviceId: decoded['deviceId'] as String?,
        projects: _stringMap(decoded['projects']),
        workspaces: _stringMap(decoded['workspaces']),
        checkoutOwners: _stringMap(decoded['checkoutOwners']),
      );
    } on Object catch (error) {
      throw FormatException(
        'Cannot read identity registry ${_stateFile.path}: $error',
      );
    }
  }

  Future<void> _writeState(_IdentityState state) async {
    final temporary = File(
      '${_stateFile.path}.$pid.'
      '${DateTime.now().toUtc().microsecondsSinceEpoch}.tmp',
    );
    try {
      final encoded = const JsonEncoder.withIndent('  ').convert({
        'version': 1,
        'deviceId': state.deviceId,
        'projects': state.projects,
        'workspaces': state.workspaces,
        'checkoutOwners': state.checkoutOwners,
      });
      await temporary.writeAsString('$encoded\n', flush: true);
      await temporary.rename(_stateFile.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<String> _projectKey(_ProjectLocation project) async {
    final repositoryDirectory = project.repositoryDirectory;
    if (repositoryDirectory == null) {
      return 'directory::${await resolveFilesystemIdentity(project.root)}';
    }

    final repositoryPath = await repositoryDirectory.resolveSymbolicLinks();
    final marker = await _identityMarker(
      directory: Directory(repositoryPath),
      filename: 'dextero-project-identity-v1',
      prefix: 'repository',
    );
    final incarnation = await resolveFilesystemIdentity(
      Directory(repositoryPath),
    );
    return 'git::$marker::$incarnation';
  }

  Future<String?> _checkoutKey(
    _ProjectLocation project,
    String projectKey,
  ) async {
    final checkoutDirectory = project.checkoutDirectory;
    if (checkoutDirectory == null) return null;

    final checkoutPath = await checkoutDirectory.resolveSymbolicLinks();
    final marker = await _identityMarker(
      directory: Directory(checkoutPath),
      filename: 'dextero-checkout-identity-v1',
      prefix: 'checkout',
    );
    final incarnation = await resolveFilesystemIdentity(
      Directory(checkoutPath),
    );
    return '$projectKey::$marker::$incarnation';
  }

  Future<String> _identityMarker({
    required Directory directory,
    required String filename,
    required String prefix,
  }) async {
    await directory.create(recursive: true);
    final markerFile = File(_join(directory.path, filename));
    final marker = await _withInProcessLock(
      'marker:${markerFile.absolute.path}',
      () async {
        final lock = await File(
          '${markerFile.path}.lock',
        ).open(mode: FileMode.append);
        var locked = false;
        try {
          await lock.lock(FileLock.blockingExclusive);
          locked = true;
          return await _readOrCreateMarker(markerFile, prefix);
        } finally {
          if (locked) await lock.unlock();
          await lock.close();
        }
      },
    );
    return marker;
  }

  Future<String> _readOrCreateMarker(File markerFile, String prefix) async {
    if (await markerFile.exists()) {
      try {
        return _validateId(await markerFile.readAsString(), prefix);
      } on Object catch (error) {
        throw FormatException(
          'Cannot read $prefix identity ${markerFile.path}: $error',
        );
      }
    }

    final marker = _identifiers.next(prefix);
    final temporary = File(
      '${markerFile.path}.$pid.'
      '${DateTime.now().toUtc().microsecondsSinceEpoch}.tmp',
    );
    try {
      await temporary.writeAsString('$marker\n', flush: true);
      await temporary.rename(markerFile.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
    return marker;
  }

  static Future<T> _withInProcessLock<T>(
    String key,
    Future<T> Function() action,
  ) async {
    final previous = _inProcessTails[key] ?? Future.value();
    final completer = Completer<void>();
    final current = completer.future;
    _inProcessTails[key] = current;
    await previous;
    try {
      return await action();
    } finally {
      completer.complete();
      if (identical(_inProcessTails[key], current)) {
        _inProcessTails.remove(key);
      }
    }
  }
}

final class _IdentityState {
  const _IdentityState({
    this.deviceId,
    this.projects = const {},
    this.workspaces = const {},
    this.checkoutOwners = const {},
  });

  final String? deviceId;
  final Map<String, String> projects;
  final Map<String, String> workspaces;
  final Map<String, String> checkoutOwners;
}

final class _ProjectLocation {
  const _ProjectLocation({
    required this.root,
    this.repositoryDirectory,
    this.checkoutDirectory,
  });

  final Directory root;
  final Directory? repositoryDirectory;
  final Directory? checkoutDirectory;
}

/// Captures every repository-local input that can change the stable project or
/// checkout identity while the selected workspace directory itself survives.
Future<String> resolveRepositoryTopologyIdentity(Directory workspace) async {
  final project = await _findProject(workspace);
  final repositoryDirectory = project.repositoryDirectory;
  final checkoutDirectory = project.checkoutDirectory;
  if (repositoryDirectory == null || checkoutDirectory == null) {
    return 'directory';
  }

  final repositoryPath = await repositoryDirectory.resolveSymbolicLinks();
  final checkoutPath = await checkoutDirectory.resolveSymbolicLinks();
  return jsonEncode({
    'kind': 'git',
    'projectRoot': await project.root.resolveSymbolicLinks(),
    'projectRootIdentity': await resolveFilesystemIdentity(project.root),
    'repositoryPath': repositoryPath,
    'repositoryIdentity': await resolveFilesystemIdentity(
      Directory(repositoryPath),
    ),
    'repositoryMarker': await _markerEvidence(
      Directory(repositoryPath),
      'dextero-project-identity-v1',
    ),
    'checkoutPath': checkoutPath,
    'checkoutIdentity': await resolveFilesystemIdentity(
      Directory(checkoutPath),
    ),
    'checkoutMarker': await _markerEvidence(
      Directory(checkoutPath),
      'dextero-checkout-identity-v1',
    ),
  });
}

Future<Map<String, Object?>> _markerEvidence(
  Directory directory,
  String filename,
) async {
  final marker = File(_join(directory.path, filename));
  final type = await FileSystemEntity.type(marker.path, followLinks: false);
  return {
    'type': _fileSystemEntityTypeName(type),
    if (type == FileSystemEntityType.file) 'value': await marker.readAsString(),
  };
}

String _fileSystemEntityTypeName(FileSystemEntityType type) {
  if (type == FileSystemEntityType.file) return 'file';
  if (type == FileSystemEntityType.directory) return 'directory';
  if (type == FileSystemEntityType.link) return 'link';
  if (type == FileSystemEntityType.notFound) return 'notFound';
  return 'other';
}

Future<_ProjectLocation> _findProject(Directory workspace) async {
  var current = workspace;
  while (true) {
    final dotGitPath = _join(current.path, '.git');
    final dotGitType = await FileSystemEntity.type(
      dotGitPath,
      followLinks: false,
    );
    if (dotGitType == FileSystemEntityType.link) {
      throw FormatException(
        'Symbolic Git metadata is unsupported: $dotGitPath',
      );
    }
    if (dotGitType == FileSystemEntityType.directory) {
      final dotGitDirectory = Directory(dotGitPath);
      return _ProjectLocation(
        root: current,
        repositoryDirectory: dotGitDirectory,
        checkoutDirectory: dotGitDirectory,
      );
    }
    if (dotGitType == FileSystemEntityType.file) {
      final dotGitFile = File(dotGitPath);
      final firstLine = (await dotGitFile.readAsLines()).firstOrNull;
      if (firstLine == null || !firstLine.startsWith('gitdir: ')) {
        throw FormatException(
          'Malformed Git worktree file: ${dotGitFile.path}',
        );
      }
      final gitDirectory = Directory(
        _resolvePath(current.path, firstLine.substring('gitdir: '.length)),
      );
      final commonDirectoryFile = File(_join(gitDirectory.path, 'commondir'));
      final Directory commonDirectory;
      if (await commonDirectoryFile.exists()) {
        commonDirectory = await _readCommonGitDirectory(
          commonDirectoryFile,
          gitDirectory,
        );
      } else {
        commonDirectory = gitDirectory;
      }
      await _validateGitDirectoryOwnership(
        workspaceRoot: current,
        dotGitFile: dotGitFile,
        gitDirectory: gitDirectory,
        commonDirectory: commonDirectory,
      );
      return _ProjectLocation(
        root: current,
        repositoryDirectory: commonDirectory,
        checkoutDirectory: gitDirectory,
      );
    }
    final parent = current.parent;
    if (parent.path == current.path) break;
    current = parent;
  }
  return _ProjectLocation(root: workspace);
}

Future<Directory> _readCommonGitDirectory(
  File commonDirectoryFile,
  Directory gitDirectory,
) async {
  final value = (await commonDirectoryFile.readAsString()).trim();
  if (value.isEmpty) {
    throw FormatException(
      'Malformed Git common-directory file: ${commonDirectoryFile.path}',
    );
  }
  return Directory(_resolvePath(gitDirectory.path, value));
}

Future<void> _validateGitDirectoryOwnership({
  required Directory workspaceRoot,
  required File dotGitFile,
  required Directory gitDirectory,
  required Directory commonDirectory,
}) async {
  if (!await gitDirectory.exists()) {
    throw FormatException('Git directory does not exist: ${gitDirectory.path}');
  }
  if (!await commonDirectory.exists()) {
    throw FormatException(
      'Git common directory does not exist: ${commonDirectory.path}',
    );
  }

  final gitPath = await gitDirectory.resolveSymbolicLinks();
  final commonPath = await commonDirectory.resolveSymbolicLinks();

  final backPointerFile = File(_join(gitDirectory.path, 'gitdir'));
  if (await backPointerFile.exists()) {
    final value = (await backPointerFile.readAsString()).trim();
    if (value.isEmpty) {
      throw FormatException(
        'Malformed Git back-pointer: ${backPointerFile.path}',
      );
    }
    final expected = await dotGitFile.resolveSymbolicLinks();
    final actualFile = File(_resolvePath(gitDirectory.path, value));
    if (!await actualFile.exists() ||
        await actualFile.resolveSymbolicLinks() != expected) {
      throw FormatException(
        'Git directory ${gitDirectory.path} does not belong to '
        '${workspaceRoot.path}',
      );
    }
    final adminDirectory = Directory(gitPath);
    if (commonPath !=
            await adminDirectory.parent.parent.resolveSymbolicLinks() ||
        _basename(adminDirectory.parent.path) != 'worktrees') {
      throw FormatException(
        'Git common directory ${commonDirectory.path} does not own '
        '${gitDirectory.path}',
      );
    }
    return;
  }

  if (commonPath != gitPath) {
    throw FormatException(
      'Git common directory ${commonDirectory.path} is not valid for '
      '${workspaceRoot.path}',
    );
  }

  // A standard --separate-git-dir repository has neither a linked-worktree
  // back-pointer nor core.worktree. Ask Git to validate the relationship that
  // the .git file declares. The host registry separately binds the resulting
  // checkout identity to this workspace's filesystem incarnation, preventing
  // another directory from reusing the same metadata.
  final result = await Process.run(
    'git',
    [
      '-C',
      workspaceRoot.path,
      'rev-parse',
      '--show-toplevel',
      '--absolute-git-dir',
      '--git-common-dir',
    ],
    includeParentEnvironment: false,
    environment: filteredProcessEnvironment(),
  );
  if (result.exitCode == 0) {
    final discovered = const LineSplitter().convert(
      (result.stdout as String).trim(),
    );
    if (discovered.length == 3) {
      final expected = await workspaceRoot.resolveSymbolicLinks();
      final actualRoot = await Directory(discovered[0]).resolveSymbolicLinks();
      final actualGitDirectory = await Directory(
        discovered[1],
      ).resolveSymbolicLinks();
      final actualCommonDirectory = await Directory(
        _resolvePath(workspaceRoot.path, discovered[2]),
      ).resolveSymbolicLinks();
      if (actualRoot == expected &&
          actualGitDirectory == gitPath &&
          actualCommonDirectory == commonPath) {
        return;
      }
    }
  }
  throw FormatException(
    'Git directory ${gitDirectory.path} does not belong to '
    '${workspaceRoot.path}',
  );
}

Map<String, String> _stringMap(Object? value) {
  if (value == null) return const {};
  if (value is! Map<String, Object?> ||
      value.values.any((entry) => entry is! String)) {
    throw const FormatException('identity mappings must contain strings');
  }
  return value.map((key, entry) => MapEntry(key, entry! as String));
}

Directory _defaultStateDirectory(Map<String, String> values) {
  final appData = values['APPDATA']?.trim();
  if (Platform.isWindows && appData != null && appData.isNotEmpty) {
    return Directory(_join(appData, 'Dextero'));
  }
  final userHome = values['HOME']?.trim();
  if (userHome == null || userHome.isEmpty) {
    throw StateError(
      'HOME is unavailable. Set DEXTERO_STATE_DIRECTORY explicitly.',
    );
  }
  if (Platform.isMacOS) {
    return Directory(
      _join(
        _join(_join(userHome, 'Library'), 'Application Support'),
        'Dextero',
      ),
    );
  }
  final xdgState = values['XDG_STATE_HOME']?.trim();
  return Directory(
    xdgState != null && xdgState.isNotEmpty
        ? _join(xdgState, 'dextero')
        : _join(_join(_join(userHome, '.local'), 'state'), 'dextero'),
  );
}

String _validateId(String value, String prefix) {
  final normalized = value.trim();
  if (!RegExp('^${prefix}_[A-Za-z0-9_-]{16,128}\$').hasMatch(normalized)) {
    throw ArgumentError.value(value, '${prefix}Id', 'is not a valid stable ID');
  }
  return normalized;
}

String _validateName(String value, String argumentName) {
  final normalized = value.trim();
  if (normalized.isEmpty ||
      normalized.length > 120 ||
      normalized.codeUnits.any((unit) => unit < 32 || unit == 127)) {
    throw ArgumentError.value(
      value,
      argumentName,
      'must contain 1 to 120 printable characters',
    );
  }
  return normalized;
}

String _basename(String path) {
  final segments = Uri.file(path).pathSegments.where((part) => part.isNotEmpty);
  return segments.isEmpty ? path : segments.last;
}

String _filesystemDisplayName(String path) {
  final raw = _basename(path);
  final sanitized = String.fromCharCodes(
    raw.runes.map((rune) => rune < 32 || rune == 127 ? 0xFFFD : rune),
  ).trim();
  if (sanitized.isEmpty) return 'Unnamed workspace';
  if (sanitized.length <= 120) return sanitized;

  final buffer = StringBuffer();
  var codeUnits = 0;
  for (final rune in sanitized.runes) {
    final width = rune > 0xFFFF ? 2 : 1;
    if (codeUnits + width > 119) break;
    buffer.writeCharCode(rune);
    codeUnits += width;
  }
  return '${buffer.toString()}…';
}

String _join(String parent, String child) =>
    '$parent${Platform.pathSeparator}$child';

String _resolvePath(String parent, String child) {
  if (paths.isAbsolute(child)) return paths.normalize(child);
  return paths.normalize(paths.join(parent, child));
}
