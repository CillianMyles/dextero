import 'dart:convert';
import 'dart:io';

import 'package:dextero_core/dextero_core.dart';
import 'package:test/test.dart';

void main() {
  test(
    'keeps device, project, and workspace identities across reloads',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'dextero-identity-',
      );
      addTearDown(() => sandbox.delete(recursive: true));
      final workspace = await Directory('${sandbox.path}/workspace').create();
      final stateFile = File('${sandbox.path}/state/identities.json');

      final first = await LocalIdentityRegistry(
        stateFile: stateFile,
        identifiers: _SequenceIdentifiers(),
      ).resolve(workspace.path);
      final second = await LocalIdentityRegistry(
        stateFile: stateFile,
        identifiers: _FailingIdentifiers(),
      ).resolve(workspace.path);

      expect(second.deviceId, first.deviceId);
      expect(second.projectId, first.projectId);
      expect(second.workspaceId, first.workspaceId);
      expect(second.projectName, 'workspace');
      expect(second.workspaceName, 'workspace');
      final state = jsonDecode(await stateFile.readAsString());
      expect(state['version'], 1);
    },
  );

  test('shares a project identity between Git worktrees', () async {
    final sandbox = await Directory.systemTemp.createTemp('dextero-worktree-');
    addTearDown(() => sandbox.delete(recursive: true));
    final project = await Directory('${sandbox.path}/project').create();
    final commonGit = await Directory('${project.path}/.git').create();
    final worktree = await Directory('${sandbox.path}/feature').create();
    final worktreeGit = await Directory(
      '${commonGit.path}/worktrees/feature',
    ).create(recursive: true);
    await File(
      '${worktree.path}/.git',
    ).writeAsString('gitdir: ${worktreeGit.path}\n');
    await File('${worktreeGit.path}/commondir').writeAsString('../..\n');
    final registry = LocalIdentityRegistry(
      stateFile: File('${sandbox.path}/state/identities.json'),
      identifiers: _SequenceIdentifiers(),
    );

    final primary = await registry.resolve(project.path);
    final feature = await registry.resolve(worktree.path);

    expect(feature.projectId, primary.projectId);
    expect(feature.workspaceId, isNot(primary.workspaceId));
  });

  test('fails closed when the identity registry is malformed', () async {
    final sandbox = await Directory.systemTemp.createTemp('dextero-identity-');
    addTearDown(() => sandbox.delete(recursive: true));
    final workspace = await Directory('${sandbox.path}/workspace').create();
    final stateFile = File('${sandbox.path}/identities.json');
    await stateFile.writeAsString('{broken');

    await expectLater(
      LocalIdentityRegistry(stateFile: stateFile).resolve(workspace.path),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects malformed host identities', () {
    expect(
      () => HostIdentity(
        deviceId: 'device-too-short',
        projectId: 'project_0123456789abcdef',
        projectName: 'Dextero',
        workspaceId: 'workspace_0123456789abcdef',
        workspaceName: 'main',
      ),
      throwsArgumentError,
    );
  });
}

final class _SequenceIdentifiers implements IdentifierGenerator {
  var _value = 0;

  @override
  String next(String prefix) =>
      '${prefix}_${(_value++).toString().padLeft(16, '0')}';
}

final class _FailingIdentifiers implements IdentifierGenerator {
  @override
  String next(String prefix) => throw StateError('identity was not stable');
}
