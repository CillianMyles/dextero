import 'dart:async';
import 'dart:io';

import 'control_identity.dart';
import 'filesystem_identity.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length < 3) {
    stderr.writeln('Invalid workspace process guard invocation');
    exitCode = 126;
    return;
  }

  final expectedFilesystemIdentity = arguments[0];
  final expectedRepositoryTopology = arguments[1];
  final executable = arguments[2];
  final commandArguments = arguments.sublist(3);
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
    stderr.writeln('Configured workspace changed after identity resolution');
    exitCode = 126;
    return;
  }

  final process = await Process.start(
    executable,
    commandArguments,
    runInShell: false,
  );
  final input = stdin.listen(
    process.stdin.add,
    onError: process.stdin.addError,
    onDone: () => unawaited(process.stdin.close()),
  );
  final output = stdout.addStream(process.stdout);
  final errors = stderr.addStream(process.stderr);
  final signalSubscriptions = <StreamSubscription<ProcessSignal>>[];
  if (!Platform.isWindows) {
    for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
      signalSubscriptions.add(
        signal.watch().listen((_) => process.kill(signal)),
      );
    }
  }

  final result = await process.exitCode;
  await input.cancel();
  await Future.wait([output, errors]);
  for (final subscription in signalSubscriptions) {
    await subscription.cancel();
  }
  exitCode = result;
}

final class _WorkspaceChanged implements Exception {
  const _WorkspaceChanged();
}
