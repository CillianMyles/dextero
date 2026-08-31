import 'dart:io';

import 'package:dextero_core/dextero_core.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late RunShellTool tool;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('run-shell-tool-');
    tool = RunShellTool(workingDirectory: root.path);
  });
  tearDown(() => root.delete(recursive: true));

  test('advertises a single command string for shell-only use', () {
    expect(tool.definition.name, 'run_shell');
    expect(tool.definition.inputSchema['required'], ['command']);
    expect((tool.definition.inputSchema['properties']! as Map).keys, [
      'command',
    ]);
    expect(tool.definition.inputSchema['additionalProperties'], isFalse);
    expect(tool.definition.description, contains('only'));
    expect(tool.definition.description, contains('shell'));
  });

  test(
    'returns the shared result schema and preserves stream whitespace',
    () async {
      final command = Platform.isWindows
          ? 'echo hello'
          : "printf 'hello\\n\\n'; printf 'warning\\n' >&2";

      expect(await tool.call({'command': command}), {
        'exit_code': 0,
        'stdout': Platform.isWindows ? 'hello\r\n' : 'hello\n\n',
        'stderr': Platform.isWindows ? '' : 'warning\n',
        'truncated': false,
      });
    },
  );

  test('supports shell operators deliberately', () async {
    final command = Platform.isWindows
        ? 'echo first && echo second'
        : 'printf first && printf second';
    final result = await tool.call({'command': command}) as JsonMap;

    expect(result['stdout'], contains('first'));
    expect(result['stdout'], contains('second'));
  });

  test('uses the configured workspace as cwd', () async {
    final result =
        await tool.call({'command': Platform.isWindows ? 'cd' : 'pwd'})
            as JsonMap;

    final processDirectory = (result['stdout']! as String).trim();
    expect(FileSystemEntity.identicalSync(processDirectory, root.path), isTrue);
  });

  test('captures non-zero exits without merging stderr into stdout', () async {
    final command = Platform.isWindows
        ? 'echo failed 1>&2 & exit /b 9'
        : 'printf out; printf failed >&2; exit 9';

    expect(await tool.call({'command': command}), {
      'exit_code': 9,
      'stdout': Platform.isWindows ? '' : 'out',
      'stderr': Platform.isWindows ? 'failed\r\n' : 'failed',
      'truncated': false,
    });
  });

  test('always reports when either output stream is truncated', () async {
    tool = RunShellTool(workingDirectory: root.path, maxOutputBytes: 5);
    final command = Platform.isWindows
        ? '<nul set /p =abcdefghij'
        : "printf 'abcdefghij'";

    expect(await tool.call({'command': command}), {
      'exit_code': 0,
      'stdout': 'abcde',
      'stderr': '',
      'truncated': true,
    });
  });

  test('rejects a missing command', () async {
    await expectLater(tool.call({}), throwsFormatException);
  });

  test('rejects a whitespace-only command', () async {
    await expectLater(tool.call({'command': '   '}), throwsFormatException);
  });
}
