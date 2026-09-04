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
    await File(
      '${worktreeGit.path}/gitdir',
    ).writeAsString('${worktree.path}/.git\n');
    final registry = LocalIdentityRegistry(
      stateFile: File('${sandbox.path}/state/identities.json'),
      identifiers: _SequenceIdentifiers(),
    );

    final primary = await registry.resolve(project.path);
    final feature = await registry.resolve(worktree.path);

    expect(feature.projectId, primary.projectId);
    expect(feature.workspaceId, isNot(primary.workspaceId));
  });

  test('rejects a gitdir owned by another checkout', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'dextero-forged-gitdir-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final project = await Directory('${sandbox.path}/project').create();
    final commonGit = await Directory('${project.path}/.git').create();
    final owner = await Directory('${sandbox.path}/owner').create();
    final ownerGit = await Directory(
      '${commonGit.path}/worktrees/owner',
    ).create(recursive: true);
    await File(
      '${owner.path}/.git',
    ).writeAsString('gitdir: ${ownerGit.path}\n');
    await File('${ownerGit.path}/commondir').writeAsString('../..\n');
    await File('${ownerGit.path}/gitdir').writeAsString('${owner.path}/.git\n');
    final forged = await Directory('${sandbox.path}/forged').create();
    await File(
      '${forged.path}/.git',
    ).writeAsString('gitdir: ${ownerGit.path}\n');
    final registry = LocalIdentityRegistry(
      stateFile: File('${sandbox.path}/state/identities.json'),
      identifiers: _SequenceIdentifiers(),
    );

    await registry.resolve(owner.path);
    await expectLater(
      registry.resolve(forged.path),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects a symbolic .git directory', () async {
    if (Platform.isWindows) return;
    final sandbox = await Directory.systemTemp.createTemp(
      'dextero-symbolic-gitdir-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final gitDirectory = await Directory('${sandbox.path}/metadata').create();
    final workspace = await Directory('${sandbox.path}/workspace').create();
    await Link('${workspace.path}/.git').create(gitDirectory.path);

    await expectLater(
      LocalIdentityRegistry(
        stateFile: File('${sandbox.path}/state/identities.json'),
      ).resolve(workspace.path),
      throwsA(isA<FormatException>()),
    );
  });

  test('accepts a standard separate Git directory', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'dextero-separate-gitdir-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final workspace = Directory('${sandbox.path}/workspace');
    final gitDirectory = Directory('${sandbox.path}/metadata');
    final initialized = await Process.run('git', [
      'init',
      '--quiet',
      '--separate-git-dir',
      gitDirectory.path,
      workspace.path,
    ]);
    expect(initialized.exitCode, 0, reason: initialized.stderr as String);

    final identity = await LocalIdentityRegistry(
      stateFile: File('${sandbox.path}/state/identities.json'),
      identifiers: _SequenceIdentifiers(),
    ).resolve(workspace.path);

    expect(identity.projectId, startsWith('project_'));
    expect(identity.workspaceId, startsWith('workspace_'));
  });

  test('rejects reuse of a standard separate Git directory', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'dextero-reused-separate-gitdir-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final owner = Directory('${sandbox.path}/owner');
    final gitDirectory = Directory('${sandbox.path}/metadata');
    final initialized = await Process.run('git', [
      'init',
      '--quiet',
      '--separate-git-dir',
      gitDirectory.path,
      owner.path,
    ]);
    expect(initialized.exitCode, 0, reason: initialized.stderr as String);
    final registry = LocalIdentityRegistry(
      stateFile: File('${sandbox.path}/state/identities.json'),
      identifiers: _SequenceIdentifiers(),
    );
    await registry.resolve(owner.path);

    final forged = await Directory('${sandbox.path}/forged').create();
    await File(
      '${forged.path}/.git',
    ).writeAsString('gitdir: ${gitDirectory.path}\n');

    await expectLater(
      registry.resolve(forged.path),
      throwsA(isA<FormatException>()),
    );
  });

  test('does not reuse identities when a Git checkout is replaced', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'dextero-replaced-repository-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final workspace = await Directory('${sandbox.path}/workspace').create();
    final gitDirectory = await Directory('${workspace.path}/.git').create();
    final stateFile = File('${sandbox.path}/state/identities.json');
    final registry = LocalIdentityRegistry(
      stateFile: stateFile,
      identifiers: _SequenceIdentifiers(),
    );

    final first = await registry.resolve(workspace.path);
    await gitDirectory.delete(recursive: true);
    await Directory(gitDirectory.path).create();
    final replacement = await registry.resolve(workspace.path);

    expect(replacement.projectId, isNot(first.projectId));
    expect(replacement.workspaceId, isNot(first.workspaceId));
  });

  test(
    'does not reuse marker identities from a copied Git repository',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'dextero-copied-repository-',
      );
      addTearDown(() => sandbox.delete(recursive: true));
      final original = await Directory('${sandbox.path}/original').create();
      final originalGit = await Directory('${original.path}/.git').create();
      final registry = LocalIdentityRegistry(
        stateFile: File('${sandbox.path}/state/identities.json'),
        identifiers: _SequenceIdentifiers(),
      );
      final first = await registry.resolve(original.path);

      final copied = await Directory('${sandbox.path}/copied').create();
      final copiedGit = await Directory('${copied.path}/.git').create();
      for (final marker in [
        'dextero-project-identity-v1',
        'dextero-checkout-identity-v1',
      ]) {
        await File(
          '${originalGit.path}/$marker',
        ).copy('${copiedGit.path}/$marker');
      }

      final copy = await registry.resolve(copied.path);

      expect(copy.projectId, isNot(first.projectId));
      expect(copy.workspaceId, isNot(first.workspaceId));
    },
  );

  test(
    'does not reuse identities when a non-Git directory is replaced',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'dextero-replaced-directory-',
      );
      addTearDown(() => sandbox.delete(recursive: true));
      final workspace = await Directory('${sandbox.path}/workspace').create();
      final registry = LocalIdentityRegistry(
        stateFile: File('${sandbox.path}/state/identities.json'),
        identifiers: _SequenceIdentifiers(),
      );

      final first = await registry.resolve(workspace.path);
      await workspace.delete(recursive: true);
      await workspace.create();
      final replacement = await registry.resolve(workspace.path);

      expect(replacement.projectId, isNot(first.projectId));
      expect(replacement.workspaceId, isNot(first.workspaceId));
      expect(Directory('${workspace.path}/.dextero').existsSync(), isFalse);
    },
  );

  test('preserves identities when a Git repository is moved', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'dextero-moved-repository-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final original = await Directory('${sandbox.path}/original').create();
    await Directory('${original.path}/.git').create();
    final workspace = await Directory('${original.path}/workspace').create();
    final registry = LocalIdentityRegistry(
      stateFile: File('${sandbox.path}/state/identities.json'),
      identifiers: _SequenceIdentifiers(),
    );

    final first = await registry.resolve(workspace.path);
    final moved = await original.rename('${sandbox.path}/moved');
    final relocated = await registry.resolve('${moved.path}/workspace');

    expect(relocated.projectId, first.projectId);
    expect(relocated.workspaceId, first.workspaceId);
    expect(relocated.projectName, 'moved');
    expect(relocated.workspaceName, 'workspace');
  });

  test('preserves identities when a non-Git directory is moved', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'dextero-moved-directory-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final original = await Directory('${sandbox.path}/original').create();
    final registry = LocalIdentityRegistry(
      stateFile: File('${sandbox.path}/state/identities.json'),
      identifiers: _SequenceIdentifiers(),
    );

    final first = await registry.resolve(original.path);
    final moved = await original.rename('${sandbox.path}/moved');
    final relocated = await registry.resolve(moved.path);

    expect(relocated.projectId, first.projectId);
    expect(relocated.workspaceId, first.workspaceId);
  });

  test('sanitizes filesystem-derived identity display names', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'dextero-display-name-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final suffix = Platform.isWindows ? '' : '\t';
    final longName = '${List.filled(130, 'x').join()}$suffix';
    final workspace = await Directory('${sandbox.path}/$longName').create();

    final identity = await LocalIdentityRegistry(
      stateFile: File('${sandbox.path}/state/identities.json'),
      identifiers: _SequenceIdentifiers(),
    ).resolve(workspace.path);

    expect(identity.projectName.length, lessThanOrEqualTo(120));
    expect(identity.workspaceName.length, lessThanOrEqualTo(120));
    expect(
      identity.workspaceName.codeUnits.any((unit) => unit < 32 || unit == 127),
      isFalse,
    );

    if (!Platform.isWindows) {
      final blank = await Directory('${sandbox.path}/   ').create();
      final blankIdentity = await LocalIdentityRegistry(
        stateFile: File('${sandbox.path}/state/identities.json'),
        identifiers: _SequenceIdentifiers(),
      ).resolve(blank.path);
      expect(blankIdentity.projectName, 'Unnamed workspace');
      expect(blankIdentity.workspaceName, 'Unnamed workspace');
    }
  });

  test('does not reuse a linked worktree identity at the same path', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'dextero-replaced-worktree-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final project = await Directory('${sandbox.path}/project').create();
    final commonGit = await Directory('${project.path}/.git').create();
    final worktree = await Directory('${sandbox.path}/feature').create();
    final worktreeGit = Directory('${commonGit.path}/worktrees/feature');

    Future<void> createWorktreeMetadata() async {
      await worktree.create();
      await worktreeGit.create(recursive: true);
      await File(
        '${worktree.path}/.git',
      ).writeAsString('gitdir: ${worktreeGit.path}\n');
      await File('${worktreeGit.path}/commondir').writeAsString('../..\n');
      await File(
        '${worktreeGit.path}/gitdir',
      ).writeAsString('${worktree.path}/.git\n');
    }

    await createWorktreeMetadata();
    final registry = LocalIdentityRegistry(
      stateFile: File('${sandbox.path}/state/identities.json'),
      identifiers: _SequenceIdentifiers(),
    );
    final first = await registry.resolve(worktree.path);

    await worktree.delete(recursive: true);
    await worktreeGit.delete(recursive: true);
    await createWorktreeMetadata();
    final replacement = await registry.resolve(worktree.path);

    expect(replacement.projectId, first.projectId);
    expect(replacement.workspaceId, isNot(first.workspaceId));
  });

  test('merges identities resolved concurrently by separate hosts', () async {
    final sandbox = await Directory.systemTemp.createTemp('dextero-hosts-');
    addTearDown(() => sandbox.delete(recursive: true));
    final firstWorkspace = await Directory('${sandbox.path}/first').create();
    final secondWorkspace = await Directory('${sandbox.path}/second').create();
    final stateFile = File('${sandbox.path}/state/identities.json');

    final resolved = await Future.wait([
      LocalIdentityRegistry(
        stateFile: stateFile,
        identifiers: _SeededIdentifiers('a'),
      ).resolve(firstWorkspace.path),
      LocalIdentityRegistry(
        stateFile: stateFile,
        identifiers: _SeededIdentifiers('b'),
      ).resolve(secondWorkspace.path),
    ]);
    final reloaded = LocalIdentityRegistry(
      stateFile: stateFile,
      identifiers: _FailingIdentifiers(),
    );

    expect(resolved[1].deviceId, resolved[0].deviceId);
    expect(
      (await reloaded.resolve(firstWorkspace.path)).workspaceId,
      resolved[0].workspaceId,
    );
    expect(
      (await reloaded.resolve(secondWorkspace.path)).workspaceId,
      resolved[1].workspaceId,
    );
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

  test('keeps Linux filesystem identity stable across timezones', () async {
    if (!Platform.isLinux) return;
    final sandbox = await Directory.systemTemp.createTemp('dextero-timezone-');
    addTearDown(() => sandbox.delete(recursive: true));
    final workspace = await Directory('${sandbox.path}/workspace').create();
    final stateFile = File('${sandbox.path}/state/identities.json');
    final helper = File(
      '${Directory.current.path}/test/fixtures/resolve_host_identity.dart',
    );

    Future<ProcessResult> resolveWithTimezone(String timezone) => Process.run(
      Platform.resolvedExecutable,
      [helper.path, stateFile.path, workspace.path],
      workingDirectory: Directory.current.path,
      environment: {'TZ': timezone},
    );

    final utc = await resolveWithTimezone('UTC');
    final newYork = await resolveWithTimezone('America/New_York');

    expect(utc.exitCode, 0, reason: utc.stderr as String);
    expect(newYork.exitCode, 0, reason: newYork.stderr as String);
    expect(newYork.stdout, utc.stdout);
  });

  test('rejects an unavailable Linux filesystem birth time', () async {
    if (!Platform.isLinux) return;
    final sandbox = await Directory.systemTemp.createTemp(
      'dextero-no-birth-time-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final workspace = await Directory('${sandbox.path}/workspace').create();
    final fakeBin = await Directory('${sandbox.path}/bin').create();
    final fakeStat = File('${fakeBin.path}/stat');
    await fakeStat.writeAsString('#!/bin/sh\nprintf "7:9:-\\n"\n');
    final chmod = await Process.run('chmod', ['+x', fakeStat.path]);
    expect(chmod.exitCode, 0, reason: chmod.stderr as String);
    final helper = File(
      '${Directory.current.path}/test/fixtures/resolve_host_identity.dart',
    );

    final result = await Process.run(
      Platform.resolvedExecutable,
      [helper.path, '${sandbox.path}/state/identities.json', workspace.path],
      workingDirectory: Directory.current.path,
      environment: {'PATH': fakeBin.path},
    );

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('filesystem birth time is unavailable'));
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

final class _SeededIdentifiers implements IdentifierGenerator {
  _SeededIdentifiers(this.seed);

  final String seed;
  var _value = 0;

  @override
  String next(String prefix) =>
      '${prefix}_${seed.padRight(15, seed)}${_value++}';
}
