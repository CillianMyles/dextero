import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../tool.dart';

final class BashTool implements Tool {
  BashTool({required String workingDirectory})
    : _workingDirectory = Directory(workingDirectory).absolute.path;

  final String _workingDirectory;

  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'bash',
    description:
        'Run a command through the platform shell in the configured workspace.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'command': {'type': 'string'},
        'timeoutMilliseconds': {
          'type': 'integer',
          'minimum': 1,
          'maximum': 300000,
          'default': 30000,
        },
        'maxOutputBytes': {
          'type': 'integer',
          'minimum': 1,
          'maximum': 10485760,
          'default': 1048576,
          'description': 'Per-stream stdout and stderr capture limit.',
        },
      },
      'required': ['command'],
      'additionalProperties': false,
    },
  );

  @override
  Future<Object?> call(JsonMap arguments) async {
    final command = arguments['command'];
    final timeoutMilliseconds = arguments['timeoutMilliseconds'] ?? 30000;
    final maxOutputBytes = arguments['maxOutputBytes'] ?? 1048576;
    if (command is! String || command.trim().isEmpty) {
      throw const FormatException('command must be a non-empty string');
    }
    if (timeoutMilliseconds is! int ||
        timeoutMilliseconds < 1 ||
        timeoutMilliseconds > 300000) {
      throw const FormatException(
        'timeoutMilliseconds must be an integer from 1 to 300000',
      );
    }
    if (maxOutputBytes is! int ||
        maxOutputBytes < 1 ||
        maxOutputBytes > 10485760) {
      throw const FormatException(
        'maxOutputBytes must be an integer from 1 to 10485760',
      );
    }

    final executable = Platform.isWindows ? 'cmd.exe' : '/bin/sh';
    final shellArguments = Platform.isWindows
        ? ['/d', '/s', '/c', command]
        : ['-c', command];
    final process = await Process.start(
      executable,
      shellArguments,
      workingDirectory: _workingDirectory,
      runInShell: false,
    );
    final stdoutFuture = _capture(process.stdout, maxOutputBytes);
    final stderrFuture = _capture(process.stderr, maxOutputBytes);
    var timedOut = false;
    final timer = Timer(Duration(milliseconds: timeoutMilliseconds), () {
      timedOut = true;
      process.kill();
    });

    final exitCode = await process.exitCode;
    timer.cancel();
    final stdout = await stdoutFuture;
    final stderr = await stderrFuture;
    return {
      'exitCode': exitCode,
      'stdout': stdout.text,
      'stderr': stderr.text,
      'stdoutTruncated': stdout.truncated,
      'stderrTruncated': stderr.truncated,
      'timedOut': timedOut,
    };
  }

  Future<_CapturedOutput> _capture(
    Stream<List<int>> stream,
    int maxBytes,
  ) async {
    final bytes = BytesBuilder(copy: false);
    var remaining = maxBytes;
    var truncated = false;
    await for (final chunk in stream) {
      if (chunk.length <= remaining) {
        bytes.add(chunk);
        remaining -= chunk.length;
      } else {
        if (remaining > 0) bytes.add(chunk.sublist(0, remaining));
        remaining = 0;
        truncated = true;
      }
    }
    return _CapturedOutput(
      utf8.decode(bytes.takeBytes(), allowMalformed: true),
      truncated,
    );
  }
}

final class _CapturedOutput {
  const _CapturedOutput(this.text, this.truncated);

  final String text;
  final bool truncated;
}
