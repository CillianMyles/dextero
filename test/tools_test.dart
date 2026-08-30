import 'dart:io';

import 'package:dart_harness_cli_spike/harness.dart';
import 'package:test/test.dart';

void main() {
  test('ReadFileTool reads inside its root and rejects traversal', () async {
    final root = await Directory.systemTemp.createTemp('dart-harness-test-');
    addTearDown(() => root.delete(recursive: true));
    await File(
      '${root.path}${Platform.pathSeparator}inside.txt',
    ).writeAsString('hello');
    final rootName = root.path.split(Platform.pathSeparator).last;
    final outsideName = '$rootName-outside.txt';
    final outside = await File(
      '${root.parent.path}${Platform.pathSeparator}$outsideName',
    ).writeAsString('nope');
    addTearDown(outside.delete);
    final tool = ReadFileTool(root: root.path);

    expect(await tool.call({'path': 'inside.txt'}), {
      'path': 'inside.txt',
      'content': 'hello',
    });
    await expectLater(
      tool.call({'path': '../$outsideName'}),
      throwsArgumentError,
    );
  });

  test('RunProcessTool executes argv directly', () async {
    final result = await RunProcessTool().call({
      'executable': Platform.resolvedExecutable,
      'arguments': ['--version'],
    });

    expect(result, isA<JsonMap>());
    expect((result as JsonMap)['exitCode'], 0);
  });
}
