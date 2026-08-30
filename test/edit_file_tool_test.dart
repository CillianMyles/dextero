import 'dart:io';

import 'package:dart_harness_cli_spike/harness.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late EditFileTool tool;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('edit-file-tool-');
    tool = EditFileTool(root: root.path);
  });
  tearDown(() => root.delete(recursive: true));

  test('advertises path and exact replacement inputs', () {
    expect(tool.definition.name, 'edit_file');
    expect(tool.definition.inputSchema['required'], [
      'path',
      'oldText',
      'newText',
    ]);
  });

  test('replaces one exact occurrence and reports UTF-8 bytes', () async {
    final file = File('${root.path}/file.txt');
    await file.writeAsString('before world after');

    expect(
      await tool.call({
        'path': 'file.txt',
        'oldText': 'world',
        'newText': 'wørld',
      }),
      {'path': 'file.txt', 'replacements': 1, 'bytes': 19},
    );
    expect(await file.readAsString(), 'before wørld after');
  });

  test('supports deletion with an empty replacement', () async {
    final file = File('${root.path}/file.txt');
    await file.writeAsString('keep remove');

    await tool.call({'path': 'file.txt', 'oldText': ' remove', 'newText': ''});

    expect(await file.readAsString(), 'keep');
  });

  test('supports multiline exact replacements', () async {
    final file = File('${root.path}/file.txt');
    await file.writeAsString('one\ntwo\nthree\n');

    await tool.call({
      'path': 'file.txt',
      'oldText': 'one\ntwo',
      'newText': 'ONE\nTWO',
    });

    expect(await file.readAsString(), 'ONE\nTWO\nthree\n');
  });

  test('does not modify the file when oldText is absent', () async {
    final file = File('${root.path}/file.txt');
    await file.writeAsString('original');

    await expectLater(
      tool.call({'path': 'file.txt', 'oldText': 'missing', 'newText': 'new'}),
      throwsStateError,
    );
    expect(await file.readAsString(), 'original');
  });

  test('does not modify the file when oldText is ambiguous', () async {
    final file = File('${root.path}/file.txt');
    await file.writeAsString('same same');

    await expectLater(
      tool.call({'path': 'file.txt', 'oldText': 'same', 'newText': 'new'}),
      throwsStateError,
    );
    expect(await file.readAsString(), 'same same');
  });

  test('treats overlapping occurrences as ambiguous', () async {
    final file = File('${root.path}/file.txt');
    await file.writeAsString('aaa');

    await expectLater(
      tool.call({'path': 'file.txt', 'oldText': 'aa', 'newText': 'b'}),
      throwsStateError,
    );
    expect(await file.readAsString(), 'aaa');
  });

  test('rejects an empty oldText', () async {
    await expectLater(
      tool.call({'path': 'file.txt', 'oldText': '', 'newText': 'new'}),
      throwsFormatException,
    );
  });

  test('rejects a missing newText', () async {
    await expectLater(
      tool.call({'path': 'file.txt', 'oldText': 'old'}),
      throwsFormatException,
    );
  });

  test('rejects traversal without changing the outside file', () async {
    final outside = File('${root.path}-outside.txt');
    await outside.writeAsString('old');
    addTearDown(outside.delete);

    await expectLater(
      tool.call({
        'path': '../${outside.uri.pathSegments.last}',
        'oldText': 'old',
        'newText': 'new',
      }),
      throwsArgumentError,
    );
    expect(await outside.readAsString(), 'old');
  });

  test(
    'rejects an outside symbolic-link target without changing it',
    () async {
      final outside = File('${root.path}-outside.txt');
      await outside.writeAsString('old');
      addTearDown(outside.delete);
      await Link('${root.path}/escape').create(outside.path);

      await expectLater(
        tool.call({'path': 'escape', 'oldText': 'old', 'newText': 'new'}),
        throwsArgumentError,
      );
      expect(await outside.readAsString(), 'old');
    },
    skip: Platform.isWindows,
  );
}
