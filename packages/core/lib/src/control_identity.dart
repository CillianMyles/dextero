import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'chat_history.dart';

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
        await lock.lock(FileLock.exclusive);
        locked = true;
        // Re-read after taking the lock so concurrent hosts merge their entries.
        final state = await _readState();
        final deviceId = state.deviceId ?? _identifiers.next('device');
        final projectId =
            state.projects[project.key] ?? _identifiers.next('project');
        final workspaceId =
            state.workspaces[workspacePath] ?? _identifiers.next('workspace');
        final changed =
            state.deviceId != deviceId ||
            state.projects[project.key] != projectId ||
            state.workspaces[workspacePath] != workspaceId;

        if (changed) {
          await _writeState(
            _IdentityState(
              deviceId: deviceId,
              projects: {...state.projects, project.key: projectId},
              workspaces: {...state.workspaces, workspacePath: workspaceId},
            ),
          );
        }

        return HostIdentity(
          deviceId: deviceId,
          projectId: projectId,
          projectName: _basename(project.root.path),
          workspaceId: workspaceId,
          workspaceName: _basename(workspacePath),
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
      });
      await temporary.writeAsString('$encoded\n', flush: true);
      await temporary.rename(_stateFile.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
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
  });

  final String? deviceId;
  final Map<String, String> projects;
  final Map<String, String> workspaces;
}

final class _ProjectLocation {
  const _ProjectLocation({required this.key, required this.root});

  final String key;
  final Directory root;
}

Future<_ProjectLocation> _findProject(Directory workspace) async {
  var current = workspace;
  while (true) {
    final dotGitDirectory = Directory(_join(current.path, '.git'));
    if (await dotGitDirectory.exists()) {
      return _ProjectLocation(
        key: await dotGitDirectory.resolveSymbolicLinks(),
        root: current,
      );
    }
    final dotGitFile = File(_join(current.path, '.git'));
    if (await dotGitFile.exists()) {
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
      final commonDirectory = await commonDirectoryFile.exists()
          ? Directory(
              _resolvePath(
                gitDirectory.path,
                (await commonDirectoryFile.readAsString()).trim(),
              ),
            )
          : gitDirectory;
      return _ProjectLocation(
        key: await commonDirectory.resolveSymbolicLinks(),
        root: current,
      );
    }
    final parent = current.parent;
    if (parent.path == current.path) break;
    current = parent;
  }
  return _ProjectLocation(key: workspace.path, root: workspace);
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

String _join(String parent, String child) =>
    '$parent${Platform.pathSeparator}$child';

String _resolvePath(String parent, String child) {
  final candidate = Directory(child);
  if (candidate.isAbsolute) return candidate.path;
  return Directory(parent).uri.resolve(child).toFilePath();
}
