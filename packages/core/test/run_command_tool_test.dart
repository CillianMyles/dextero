import 'dart:io';

import 'package:dextero_core/dextero_core.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late RunCommandTool tool;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('run-command-tool-');
    tool = RunCommandTool(workingDirectory: root.path);
  });
  tearDown(() => root.delete(recursive: true));

  test('advertises direct command execution as the default', () {
    expect(tool.definition.name, 'run_command');
    expect(tool.definition.inputSchema['required'], ['command']);
    expect((tool.definition.inputSchema['properties']! as Map).keys, [
      'command',
      'arguments',
    ]);
    expect(tool.definition.inputSchema['additionalProperties'], isFalse);
    expect(tool.definition.description, contains('default'));
    expect(tool.definition.description, contains('without a shell'));
  });

  test(
    'returns the shared result schema and preserves stream whitespace',
    () async {
      final script = await _script(
        root,
        "stdout.write('hello\\n\\n'); stderr.write('warning\\n');",
      );

      expect(
        await tool.call({
          'command': Platform.resolvedExecutable,
          'arguments': [script.path],
        }),
        {
          'exit_code': 0,
          'stdout': 'hello\n\n',
          'stderr': 'warning\n',
          'truncated': false,
        },
      );
    },
  );

  test(
    'preserves structured argument boundaries without shell expansion',
    () async {
      final script = await _script(root, 'stdout.write(arguments.join("|"));');

      final result =
          await tool.call({
                'command': Platform.resolvedExecutable,
                'arguments': [
                  script.path,
                  'hello world',
                  r'$(not-a-command)',
                  'a;b',
                ],
              })
              as JsonMap;

      expect(result['stdout'], r'hello world|$(not-a-command)|a;b');
    },
  );

  test('uses the configured working directory', () async {
    final script = await _script(root, 'stdout.write(Directory.current.path);');

    final result =
        await tool.call({
              'command': Platform.resolvedExecutable,
              'arguments': [script.path],
            })
            as JsonMap;

    expect(
      FileSystemEntity.identicalSync(result['stdout']! as String, root.path),
      isTrue,
    );
  });

  test('captures non-zero exits without merging stderr into stdout', () async {
    final script = await _script(
      root,
      "stdout.write('out'); stderr.write('failed'); exitCode = 7;",
    );

    expect(
      await tool.call({
        'command': Platform.resolvedExecutable,
        'arguments': [script.path],
      }),
      {'exit_code': 7, 'stdout': 'out', 'stderr': 'failed', 'truncated': false},
    );
  });

  test(
    'reports bounded incremental output metadata without its content',
    () async {
      final updates = <ToolOutputUpdate>[];
      final script = await _script(
        root,
        "stdout.write('secret output'); stderr.write('secret error');",
      );

      await tool.call({
        'command': Platform.resolvedExecutable,
        'arguments': [script.path],
      }, onOutput: updates.add);

      expect(updates.map((update) => update.stream).toSet(), {
        'stdout',
        'stderr',
      });
      expect(updates.every((update) => update.byteCount > 0), isTrue);
    },
  );

  test('always reports when either output stream is truncated', () async {
    tool = RunCommandTool(workingDirectory: root.path, maxOutputBytes: 5);
    final script = await _script(
      root,
      "stdout.write('abcdefghij'); stderr.write('ABCDEFGHIJ');",
    );

    expect(
      await tool.call({
        'command': Platform.resolvedExecutable,
        'arguments': [script.path],
      }),
      {'exit_code': 0, 'stdout': 'abcde', 'stderr': 'ABCDE', 'truncated': true},
    );
  });

  test('defaults omitted arguments to an empty list', () async {
    final script = await _script(root, 'stdout.write(arguments.length);');
    final result =
        await tool.call({
              'command': Platform.resolvedExecutable,
              'arguments': [script.path],
            })
            as JsonMap;
    expect(result['stdout'], '0');
  });

  test('rejects an empty command', () async {
    await expectLater(tool.call({'command': ''}), throwsFormatException);
  });

  test('rejects a non-list arguments value', () async {
    await expectLater(
      tool.call({'command': 'dart', 'arguments': 'version'}),
      throwsFormatException,
    );
  });

  test('rejects a non-string argument', () async {
    await expectLater(
      tool.call({
        'command': 'dart',
        'arguments': [1],
      }),
      throwsFormatException,
    );
  });

  test('reports a missing command', () async {
    await expectLater(
      tool.call({'command': 'definitely-not-a-real-command-12345'}),
      throwsA(isA<ProcessException>()),
    );
  });
}

Future<File> _script(Directory root, String body) async {
  return File('${root.path}/script.dart').writeAsString(
    "import 'dart:io';\nvoid main(List<String> arguments) { $body }\n",
  );
}
