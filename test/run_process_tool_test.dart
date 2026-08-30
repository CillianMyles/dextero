import 'dart:io';

import 'package:dextero/harness.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late RunProcessTool tool;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('run-process-tool-');
    tool = RunProcessTool(workingDirectory: root.path);
  });
  tearDown(() => root.delete(recursive: true));

  test('advertises executable and string-array arguments', () {
    expect(tool.definition.name, 'run_process');
    expect(tool.definition.inputSchema['required'], ['executable']);
  });

  test(
    'executes an executable directly and preserves stdout whitespace',
    () async {
      final script = await _script(root, "stdout.write('hello\\n\\n');");

      expect(
        await tool.call({
          'executable': Platform.resolvedExecutable,
          'arguments': [script.path],
        }),
        {'exitCode': 0, 'stdout': 'hello\n\n', 'stderr': ''},
      );
    },
  );

  test('preserves argv boundaries without shell interpolation', () async {
    final script = await _script(root, 'stdout.write(arguments.join("|"));');

    final result =
        await tool.call({
              'executable': Platform.resolvedExecutable,
              'arguments': [
                script.path,
                'hello world',
                r'$(not-a-command)',
                'a;b',
              ],
            })
            as JsonMap;

    expect(result['stdout'], r'hello world|$(not-a-command)|a;b');
  });

  test('uses the configured working directory', () async {
    final script = await _script(root, 'stdout.write(Directory.current.path);');

    final result =
        await tool.call({
              'executable': Platform.resolvedExecutable,
              'arguments': [script.path],
            })
            as JsonMap;

    expect(result['stdout'], root.path);
  });

  test('captures stderr and a non-zero exit code', () async {
    final script = await _script(
      root,
      "stderr.write('failed\\n'); exitCode = 7;",
    );

    final result = await tool.call({
      'executable': Platform.resolvedExecutable,
      'arguments': [script.path],
    });

    expect(result, {'exitCode': 7, 'stdout': '', 'stderr': 'failed\n'});
  });

  test('defaults omitted arguments to an empty list', () async {
    final script = await _script(root, 'stdout.write(arguments.length);');
    final result =
        await tool.call({
              'executable': Platform.resolvedExecutable,
              'arguments': [script.path],
            })
            as JsonMap;
    expect(result['stdout'], '0');
  });

  test('rejects an empty executable', () async {
    await expectLater(tool.call({'executable': ''}), throwsFormatException);
  });

  test('rejects a non-list arguments value', () async {
    await expectLater(
      tool.call({'executable': 'dart', 'arguments': 'version'}),
      throwsFormatException,
    );
  });

  test('rejects a non-string argument', () async {
    await expectLater(
      tool.call({
        'executable': 'dart',
        'arguments': [1],
      }),
      throwsFormatException,
    );
  });

  test('reports a missing executable', () async {
    await expectLater(
      tool.call({'executable': 'definitely-not-a-real-executable-12345'}),
      throwsA(isA<ProcessException>()),
    );
  });
}

Future<File> _script(Directory root, String body) async {
  return File('${root.path}/script.dart').writeAsString(
    "import 'dart:io';\nvoid main(List<String> arguments) { $body }\n",
  );
}
