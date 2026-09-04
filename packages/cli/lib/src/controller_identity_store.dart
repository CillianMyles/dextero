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

    if (await _stateFile.exists()) {
      try {
        final decoded = jsonDecode(await _stateFile.readAsString());
        if (decoded is! Map<String, Object?> || decoded['version'] != 1) {
          throw const FormatException('unsupported controller state version');
        }
        final validated = ControllerIdentities.validated(
          id: decoded['controllerId']! as String,
          name: effectiveName,
        );
        return ControllerIdentity(id: validated.id, name: validated.name);
      } on Object catch (error) {
        throw FormatException(
          'Cannot read controller identity ${_stateFile.path}: $error',
        );
      }
    }

    final id = ControllerIdentities.createId();
    await _stateFile.parent.create(recursive: true);
    await _stateFile.writeAsString(
      '${jsonEncode({'version': 1, 'controllerId': id})}\n',
      flush: true,
    );
    return ControllerIdentity(id: id, name: effectiveName);
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
