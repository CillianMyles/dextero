import 'dart:io';

import 'package:dextero_core/dextero_core.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late ListFilesTool tool;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('list-files-tool-');
    tool = ListFilesTool(root: root.path);
  });
  tearDown(() => root.delete(recursive: true));

  test('advertises optional path and recursive inputs', () {
    expect(tool.definition.name, 'list_files');
    expect(tool.definition.inputSchema['additionalProperties'], isFalse);
    expect(tool.definition.inputSchema.containsKey('required'), isFalse);
  });

  test('lists the workspace root non-recursively by default', () async {
    await File('${root.path}/b.txt').writeAsString('b');
    await File('${root.path}/a.txt').writeAsString('a');
    await Directory('${root.path}/nested').create();
    await File('${root.path}/nested/hidden.txt').writeAsString('nested');

    expect(await tool.call({}), {
      'path': '.',
      'entries': [
        {'path': 'a.txt', 'type': 'file'},
        {'path': 'b.txt', 'type': 'file'},
        {'path': 'nested', 'type': 'directory'},
      ],
    });
  });

  test('lists recursively in deterministic path order', () async {
    await Directory('${root.path}/z').create();
    await File('${root.path}/z/file.txt').writeAsString('z');
    await Directory('${root.path}/a').create();
    await File('${root.path}/a/file.txt').writeAsString('a');

    final result = await tool.call({'recursive': true}) as JsonMap;

    expect(result['entries'], [
      {'path': 'a', 'type': 'directory'},
      {'path': 'a/file.txt', 'type': 'file'},
      {'path': 'z', 'type': 'directory'},
      {'path': 'z/file.txt', 'type': 'file'},
    ]);
  });

  test(
    'lists a nested directory using workspace-relative output paths',
    () async {
      await Directory('${root.path}/nested').create();
      await File('${root.path}/nested/file.txt').writeAsString('a');

      expect(await tool.call({'path': 'nested'}), {
        'path': 'nested',
        'entries': [
          {'path': 'nested/file.txt', 'type': 'file'},
        ],
      });
    },
  );

  test('returns an empty list for an empty directory', () async {
    await Directory('${root.path}/empty').create();
    expect(await tool.call({'path': 'empty'}), {
      'path': 'empty',
      'entries': <JsonMap>[],
    });
  });

  test('rejects replacement after materializing entry types', () async {
    await File('${root.path}/entry').writeAsString('original');
    final boundary = await WorkspaceBoundary.capture(root.path);
    tool = ListFilesTool(
      root: boundary.root,
      boundary: boundary,
      beforeFinalValidation: () async {
        await root.delete(recursive: true);
        await root.create();
        await Directory('${root.path}/entry').create();
      },
    );

    await expectLater(tool.call({}), throwsA(isA<FileSystemException>()));
  });

  test('rejects a non-boolean recursive value', () async {
    await expectLater(tool.call({'recursive': 'yes'}), throwsFormatException);
  });

  test('rejects a file as the listing root', () async {
    await File('${root.path}/file.txt').writeAsString('a');
    await expectLater(tool.call({'path': 'file.txt'}), throwsArgumentError);
  });

  test('rejects traversal to an outside directory', () async {
    final outside = Directory('${root.path}-outside');
    await outside.create();
    addTearDown(() => outside.delete(recursive: true));

    await expectLater(
      tool.call({'path': '../${outside.uri.pathSegments.last}'}),
      throwsArgumentError,
    );
  });

  test('reports symbolic links but does not recursively follow them', () async {
    final outside = Directory('${root.path}-outside');
    await outside.create();
    await File('${outside.path}/private.txt').writeAsString('private');
    addTearDown(() => outside.delete(recursive: true));
    await Link('${root.path}/outside-link').create(outside.path);

    final result = await tool.call({'recursive': true}) as JsonMap;

    expect(result['entries'], [
      {'path': 'outside-link', 'type': 'link'},
    ]);
  }, skip: Platform.isWindows);
}
