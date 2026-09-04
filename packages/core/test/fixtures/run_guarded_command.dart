import 'dart:io';

import 'package:dextero_core/dextero_core.dart';

Future<void> main(List<String> arguments) async {
  final boundary = await WorkspaceBoundary.capture(arguments[0]);
  final result =
      await RunCommandTool(
            workingDirectory: boundary.root,
            workspaceBoundary: boundary,
          ).call({
            'command': Platform.resolvedExecutable,
            'arguments': ['--version'],
          })
          as JsonMap;
  if (result['exit_code'] != 0) {
    throw StateError('guarded command failed: $result');
  }
}
