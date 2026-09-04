import 'dart:io';

import 'package:dextero_core/dextero_core.dart';
import 'package:test/test.dart';

void main() {
  test('rejects a workspace that becomes a Git repository', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'dextero-boundary-git-init-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final workspace = await Directory('${sandbox.path}/workspace').create();
    final boundary = await WorkspaceBoundary.capture(workspace.path);

    final initialized = await Process.run('git', [
      'init',
      '--quiet',
      workspace.path,
    ]);
    expect(initialized.exitCode, 0, reason: initialized.stderr as String);

    await expectLater(boundary.validate(), throwsA(isA<FileSystemException>()));
  });

  test('rejects replacement Git metadata under the same workspace', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'dextero-boundary-repository-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final workspace = await Directory('${sandbox.path}/workspace').create();
    final gitDirectory = await Directory('${workspace.path}/.git').create();
    final registry = LocalIdentityRegistry(
      stateFile: File('${sandbox.path}/state/identities.json'),
    );
    await registry.resolve(workspace.path);
    final boundary = await WorkspaceBoundary.capture(workspace.path);

    await gitDirectory.delete(recursive: true);
    await Directory(gitDirectory.path).create();

    await expectLater(boundary.validate(), throwsA(isA<FileSystemException>()));
  });

  test('rejects changed repository identity markers', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'dextero-boundary-marker-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final workspace = await Directory('${sandbox.path}/workspace').create();
    final gitDirectory = await Directory('${workspace.path}/.git').create();
    final registry = LocalIdentityRegistry(
      stateFile: File('${sandbox.path}/state/identities.json'),
    );
    await registry.resolve(workspace.path);
    final boundary = await WorkspaceBoundary.capture(workspace.path);

    await File(
      '${gitDirectory.path}/dextero-project-identity-v1',
    ).writeAsString('repository_0000000000000000\n');

    await expectLater(boundary.validate(), throwsA(isA<FileSystemException>()));
  });
}
