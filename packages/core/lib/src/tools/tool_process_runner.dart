import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../cancellation.dart';
import '../process_environment.dart';
import '../tool.dart';
import '../workspace_boundary.dart';

/// Runs a process with bounded, separate stdout and stderr capture.
final class ToolProcessRunner {
  ToolProcessRunner({
    required String workingDirectory,
    this.workspaceBoundary,
    this.timeout = const Duration(seconds: 30),
    this.maxOutputBytes = 1024 * 1024,
  }) : workingDirectory = Directory(workingDirectory).absolute.path {
    if (timeout <= Duration.zero || timeout > const Duration(minutes: 5)) {
      throw ArgumentError.value(
        timeout,
        'timeout',
        'must be greater than zero and at most five minutes',
      );
    }
    if (maxOutputBytes < 1 || maxOutputBytes > 10 * 1024 * 1024) {
      throw ArgumentError.value(
        maxOutputBytes,
        'maxOutputBytes',
        'must be from 1 byte to 10 MiB',
      );
    }
  }

  final String workingDirectory;
  final WorkspaceBoundary? workspaceBoundary;
  final Duration timeout;
  final int maxOutputBytes;

  Future<JsonMap> run(
    String command,
    List<String> arguments, {
    CancellationToken? cancellationToken,
    ToolOutputSink? onOutput,
  }) async {
    cancellationToken?.throwIfCancellationRequested();
    await workspaceBoundary?.validate();
    final process = await Process.start(
      command,
      arguments,
      workingDirectory: workingDirectory,
      runInShell: false,
      includeParentEnvironment: false,
      environment: filteredProcessEnvironment(),
    );
    final stdoutFuture = _capture(process.stdout, 'stdout', onOutput);
    final stderrFuture = _capture(process.stderr, 'stderr', onOutput);
    final termination = Completer<_TerminationReason>();
    final timer = Timer(
      timeout,
      () => termination.complete(_TerminationReason.timeout),
    );
    if (cancellationToken != null) {
      unawaited(
        cancellationToken.whenCancelled.then((_) {
          if (!termination.isCompleted) {
            termination.complete(_TerminationReason.cancelled);
          }
        }),
      );
    }

    final naturalExit = process.exitCode.then((_) => _TerminationReason.exit);
    final reason = await Future.any([naturalExit, termination.future]);
    if (reason != _TerminationReason.exit) {
      await terminateProcessTree(process);
    }
    final exitCode = await process.exitCode;
    timer.cancel();
    final stdout = await stdoutFuture;
    final stderr = await stderrFuture;
    if (reason == _TerminationReason.cancelled) {
      throw const RunCancelledException();
    }
    return {
      'exit_code': exitCode,
      'stdout': stdout.text,
      'stderr': stderr.text,
      'truncated': stdout.truncated || stderr.truncated,
      if (reason == _TerminationReason.timeout) 'timed_out': true,
    };
  }

  Future<_CapturedOutput> _capture(
    Stream<List<int>> stream,
    String streamName,
    ToolOutputSink? onOutput,
  ) async {
    final bytes = BytesBuilder(copy: false);
    var remaining = maxOutputBytes;
    var truncated = false;
    await for (final chunk in stream) {
      await onOutput?.call(
        ToolOutputUpdate(stream: streamName, byteCount: chunk.length),
      );
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

enum _TerminationReason { exit, timeout, cancelled }

final class _CapturedOutput {
  const _CapturedOutput(this.text, this.truncated);

  final String text;
  final bool truncated;
}
