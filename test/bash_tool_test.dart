import 'dart:io';

import 'package:dextero/harness.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late BashTool tool;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('bash-tool-');
    tool = BashTool(workingDirectory: root.path);
  });
  tearDown(() => root.delete(recursive: true));

  test('advertises the shell and timeout boundary', () {
    expect(tool.definition.name, 'bash');
    expect(tool.definition.inputSchema['required'], ['command']);
    expect(tool.definition.inputSchema['additionalProperties'], isFalse);
  });

  test('runs a shell command and preserves stdout whitespace', () async {
    final result = await tool.call({
      'command': Platform.isWindows ? 'echo hello' : "printf 'hello\\n\\n'",
    });

    expect(result, {
      'exitCode': 0,
      'stdout': Platform.isWindows ? 'hello\r\n' : 'hello\n\n',
      'stderr': '',
      'stdoutTruncated': false,
      'stderrTruncated': false,
      'timedOut': false,
    });
  });

  test('supports shell operators deliberately', () async {
    final command = Platform.isWindows
        ? 'echo first && echo second'
        : "printf first && printf second";
    final result = await tool.call({'command': command}) as JsonMap;

    expect(result['stdout'], contains('first'));
    expect(result['stdout'], contains('second'));
  });

  test('uses the configured workspace as cwd', () async {
    final result =
        await tool.call({'command': Platform.isWindows ? 'cd' : 'pwd'})
            as JsonMap;

    expect((result['stdout']! as String).trim(), root.path);
  });

  test('captures stderr and non-zero exit status', () async {
    final command = Platform.isWindows
        ? 'echo failed 1>&2 & exit /b 9'
        : "printf failed >&2; exit 9";
    final result = await tool.call({'command': command}) as JsonMap;

    expect(result['exitCode'], 9);
    expect(result['stderr'], 'failed');
    expect(result['timedOut'], isFalse);
  });

  test('caps stdout while draining the process to completion', () async {
    final command = Platform.isWindows
        ? '<nul set /p =abcdefghij'
        : "printf 'abcdefghij'";
    final result =
        await tool.call({'command': command, 'maxOutputBytes': 5}) as JsonMap;

    expect(result['exitCode'], 0);
    expect(result['stdout'], 'abcde');
    expect(result['stdoutTruncated'], isTrue);
    expect(result['stderrTruncated'], isFalse);
  });

  test('kills a command after its timeout', () async {
    final result =
        await tool.call({
              'command': 'while :; do :; done',
              'timeoutMilliseconds': 30,
            })
            as JsonMap;

    expect(result['timedOut'], isTrue);
    expect(result['exitCode'], isNot(0));
  }, skip: Platform.isWindows);

  test('rejects a missing command', () async {
    await expectLater(tool.call({}), throwsFormatException);
  });

  test('rejects a whitespace-only command', () async {
    await expectLater(tool.call({'command': '   '}), throwsFormatException);
  });

  test('rejects a non-integer timeout', () async {
    await expectLater(
      tool.call({'command': 'echo ok', 'timeoutMilliseconds': 1.5}),
      throwsFormatException,
    );
  });

  test('rejects a zero timeout', () async {
    await expectLater(
      tool.call({'command': 'echo ok', 'timeoutMilliseconds': 0}),
      throwsFormatException,
    );
  });

  test('rejects a timeout above five minutes', () async {
    await expectLater(
      tool.call({'command': 'echo ok', 'timeoutMilliseconds': 300001}),
      throwsFormatException,
    );
  });

  test('rejects a zero output limit', () async {
    await expectLater(
      tool.call({'command': 'echo ok', 'maxOutputBytes': 0}),
      throwsFormatException,
    );
  });

  test('rejects an output limit above ten MiB', () async {
    await expectLater(
      tool.call({'command': 'echo ok', 'maxOutputBytes': 10485761}),
      throwsFormatException,
    );
  });
}
