import 'dart:io';

import 'package:dextero_core/dextero_core.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late ReadFileTool tool;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('read-file-tool-');
    tool = ReadFileTool(root: root.path);
  });
  tearDown(() => root.delete(recursive: true));

  test('advertises a closed object schema', () {
    expect(tool.definition.name, 'read_file');
    expect(tool.definition.inputSchema['additionalProperties'], isFalse);
    expect(tool.definition.inputSchema['required'], ['path']);
  });

  test('reads UTF-8 content without changing whitespace', () async {
    await File('${root.path}/hello.txt').writeAsString('héllo\n\n');

    expect(await tool.call({'path': 'hello.txt'}), {
      'path': 'hello.txt',
      'content': 'héllo\n\n',
    });
  });

  test('reads a nested file', () async {
    await Directory('${root.path}/nested').create();
    await File('${root.path}/nested/file.txt').writeAsString('inside');

    expect(await tool.call({'path': 'nested/file.txt'}), {
      'path': 'nested/file.txt',
      'content': 'inside',
    });
  });

  test('rejects a missing path argument', () async {
    await expectLater(tool.call({}), throwsFormatException);
  });

  test('rejects an empty path', () async {
    await expectLater(tool.call({'path': ''}), throwsFormatException);
  });

  test('rejects a non-string path', () async {
    await expectLater(tool.call({'path': 42}), throwsFormatException);
  });

  test('reports a missing file', () async {
    await expectLater(
      tool.call({'path': 'missing.txt'}),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('rejects a directory', () async {
    await Directory('${root.path}/directory').create();
    await expectLater(tool.call({'path': 'directory'}), throwsArgumentError);
  });

  test('rejects an absolute path', () async {
    await expectLater(
      tool.call({'path': '${root.path}/file.txt'}),
      throwsArgumentError,
    );
  });

  test('rejects parent traversal to an existing file', () async {
    final outside = File('${root.path}-outside.txt');
    await outside.writeAsString('private');
    addTearDown(outside.delete);

    await expectLater(
      tool.call({'path': '../${outside.uri.pathSegments.last}'}),
      throwsArgumentError,
    );
  });

  test(
    'rejects a symbolic link whose target is outside the workspace',
    () async {
      final outside = File('${root.path}-outside.txt');
      await outside.writeAsString('private');
      addTearDown(outside.delete);
      await Link('${root.path}/escape').create(outside.path);

      await expectLater(tool.call({'path': 'escape'}), throwsArgumentError);
    },
    skip: Platform.isWindows,
  );

  test('rejects access after the workspace directory is replaced', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'read-file-replaced-workspace-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final workspace = await Directory('${sandbox.path}/workspace').create();
    final boundary = await WorkspaceBoundary.capture(workspace.path);
    final guarded = ReadFileTool(root: boundary.root, boundary: boundary);
    await workspace.rename('${sandbox.path}/original');
    await workspace.create();
    await File('${workspace.path}/secret.txt').writeAsString('replacement');

    await expectLater(
      guarded.call({'path': 'secret.txt'}),
      throwsA(isA<FileSystemException>()),
    );
  });
}
