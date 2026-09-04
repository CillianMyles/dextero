import 'dart:io';

import 'package:dextero_core/src/tools/workspace_path.dart';
import 'package:test/test.dart';

void main() {
  late Directory sandbox;
  late Directory workspace;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('workspace-path-race-');
    workspace = await Directory('${sandbox.path}/workspace').create();
  });

  tearDown(() => sandbox.delete(recursive: true));

  test('opens an unchanged file through a verified handle', () async {
    final selected = File('${workspace.path}/selected.txt');
    await selected.writeAsString('selected');

    final file = await WorkspacePath(
      workspace.path,
    ).openExistingFile('selected.txt');
    try {
      expect(await file.read(await file.length()), 'selected'.codeUnits);
    } finally {
      await file.close();
    }
  });

  test('rejects same-path replacement between validation and open', () async {
    final selected = File('${workspace.path}/selected.txt');
    await selected.writeAsString('selected');
    final replacement = File('${sandbox.path}/replacement.txt');
    await replacement.writeAsString('replacement');
    final path = WorkspacePath(
      workspace.path,
      beforeFileOpen: (path) async {
        await File(path).delete();
        await replacement.copy(path);
      },
    );

    await expectLater(
      path.openExistingFile('selected.txt'),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('rejects an outside symlink swapped in before open', () async {
    final selected = File('${workspace.path}/selected.txt');
    await selected.writeAsString('selected');
    final outside = File('${sandbox.path}/outside.txt');
    await outside.writeAsString('outside');
    final path = WorkspacePath(
      workspace.path,
      beforeFileOpen: (path) async {
        await File(path).delete();
        await Link(path).create(outside.path);
      },
    );

    await expectLater(
      path.openExistingFile('selected.txt'),
      throwsA(isA<FileSystemException>()),
    );
  }, skip: Platform.isWindows);
}
