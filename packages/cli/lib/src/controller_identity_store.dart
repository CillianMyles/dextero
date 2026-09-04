import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dextero_server/dextero_client.dart';

/// Persists one stable identity for this CLI installation.
final class CliControllerIdentityStore {
  CliControllerIdentityStore({required File stateFile})
    : _stateFile = stateFile;

  factory CliControllerIdentityStore.fromEnvironment(
    Map<String, String> values,
  ) {
    final configured = values['DEXTERO_STATE_DIRECTORY']?.trim();
    final stateDirectory = configured == null || configured.isEmpty
        ? _defaultStateDirectory(values)
        : Directory(configured).absolute;
    return CliControllerIdentityStore(
      stateFile: File(
        '${stateDirectory.path}${Platform.pathSeparator}cli-controller-v1.json',
      ),
    );
  }

  final File _stateFile;
  static final Map<String, Future<void>> _inProcessTails = {};
  static var _temporarySequence = 0;

  Future<ControllerIdentity> load(Map<String, String> environment) async {
    final name = environment['DEXTERO_CONTROLLER_NAME']?.trim();
    final effectiveName = name == null || name.isEmpty ? 'Dextero CLI' : name;
    final override = environment['DEXTERO_CONTROLLER_ID']?.trim();
    if (override != null && override.isNotEmpty) {
      final validated = ControllerIdentities.validated(
        id: override,
        name: effectiveName,
      );
      return ControllerIdentity(id: validated.id, name: validated.name);
    }

    return _withInProcessLock(_stateFile.absolute.path, () async {
      await _stateFile.parent.create(recursive: true);
      final lock = await File(
        '${_stateFile.path}.lock',
      ).open(mode: FileMode.append);
      var locked = false;
      try {
        await lock.lock(FileLock.exclusive);
        locked = true;
        final existing = await _read(effectiveName);
        if (existing != null) return existing;

        final id = ControllerIdentities.createId();
        await _write(id);
        final validated = ControllerIdentities.validated(
          id: id,
          name: effectiveName,
        );
        return ControllerIdentity(id: validated.id, name: validated.name);
      } finally {
        if (locked) await lock.unlock();
        await lock.close();
      }
    });
  }

  Future<ControllerIdentity?> _read(String name) async {
    if (!await _stateFile.exists()) return null;
    try {
      final decoded = jsonDecode(await _stateFile.readAsString());
      if (decoded is! Map<String, Object?> || decoded['version'] != 1) {
        throw const FormatException('unsupported controller state version');
      }
      final validated = ControllerIdentities.validated(
        id: decoded['controllerId']! as String,
        name: name,
      );
      return ControllerIdentity(id: validated.id, name: validated.name);
    } on Object catch (error) {
      throw FormatException(
        'Cannot read controller identity ${_stateFile.path}: $error',
      );
    }
  }

  Future<void> _write(String id) async {
    final temporary = File(
      '${_stateFile.path}.$pid.${_temporarySequence++}.tmp',
    );
    try {
      await temporary.writeAsString(
        '${jsonEncode({'version': 1, 'controllerId': id})}\n',
        flush: true,
      );
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

Directory _defaultStateDirectory(Map<String, String> values) {
  final appData = values['APPDATA']?.trim();
  if (Platform.isWindows && appData != null && appData.isNotEmpty) {
    return Directory('$appData${Platform.pathSeparator}Dextero');
  }
  final userHome = values['HOME']?.trim();
  if (userHome == null || userHome.isEmpty) {
    throw StateError(
      'HOME is unavailable. Set DEXTERO_STATE_DIRECTORY explicitly.',
    );
  }
  if (Platform.isMacOS) {
    return Directory(
      '$userHome${Platform.pathSeparator}Library'
      '${Platform.pathSeparator}Application Support'
      '${Platform.pathSeparator}Dextero',
    );
  }
  final xdgState = values['XDG_STATE_HOME']?.trim();
  return Directory(
    xdgState != null && xdgState.isNotEmpty
        ? '$xdgState${Platform.pathSeparator}dextero'
        : '$userHome${Platform.pathSeparator}.local'
              '${Platform.pathSeparator}state'
              '${Platform.pathSeparator}dextero',
  );
}
