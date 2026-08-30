import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.length != 2 || args.first != '--run') {
    stderr.writeln('usage: harness --run <command>');
    exitCode = 64;
    return;
  }

  final shell = Platform.isWindows ? 'cmd' : '/bin/sh';
  final shellArgs = Platform.isWindows ? ['/c', args.last] : ['-c', args.last];
  final result = await Process.run(shell, shellArgs);
  stdout.writeln(
    jsonEncode({
      'platform': Platform.operatingSystem,
      'exitCode': result.exitCode,
      'stdout': result.stdout.toString().trim(),
      'stderr': result.stderr.toString().trim(),
    }),
  );
  exitCode = result.exitCode;
}

