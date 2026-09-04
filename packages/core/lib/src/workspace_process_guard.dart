import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'control_identity.dart';
import 'filesystem_identity.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length < 4) {
    stderr.writeln('Invalid workspace process guard invocation');
    exitCode = 126;
    return;
  }

  final expectedFilesystemIdentity = arguments[0];
  final expectedRepositoryTopology = arguments[1];
  final startupPath = arguments[2];
  final executable = arguments[3];
  final commandArguments = arguments.sublist(4);
  final directory = Directory.current;
  try {
    final actualFilesystemIdentity = await resolveFilesystemIdentity(directory);
    final actualRepositoryTopology = await resolveRepositoryTopologyIdentity(
      directory,
    );
    if (actualFilesystemIdentity != expectedFilesystemIdentity ||
        actualRepositoryTopology != expectedRepositoryTopology) {
      throw const _WorkspaceChanged();
    }
  } on Object {
    await _reportStartup(startupPath, const {'status': 'rejected'});
    stderr.writeln('Configured workspace changed after identity resolution');
    exitCode = 126;
    return;
  }

  late final Process process;
  try {
    process = await Process.start(
      executable,
      commandArguments,
      runInShell: false,
      mode: ProcessStartMode.inheritStdio,
    );
  } on ProcessException catch (error) {
    await _reportStartup(startupPath, {
      'status': 'launchError',
      'message': error.message,
      'errorCode': error.errorCode,
    });
    exitCode = 126;
    return;
  }
  try {
    await _reportStartup(startupPath, const {'status': 'ready'});
  } on Object catch (error) {
    process.kill();
    stderr.writeln('Cannot report guarded process startup: $error');
    exitCode = 126;
    return;
  }
  final signalSubscriptions = <StreamSubscription<ProcessSignal>>[];
  if (!Platform.isWindows) {
    for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
      signalSubscriptions.add(
        signal.watch().listen((_) => process.kill(signal)),
      );
    }
  }

  final result = await process.exitCode;
  for (final subscription in signalSubscriptions) {
    await subscription.cancel();
  }
  exitCode = result;
}

Future<void> _reportStartup(String path, Map<String, Object?> status) async {
  final target = File(path);
  final temporary = File('$path.$pid.tmp');
  await temporary.writeAsString(jsonEncode(status), flush: true);
  await temporary.rename(target.path);
}

final class _WorkspaceChanged implements Exception {
  const _WorkspaceChanged();
}
