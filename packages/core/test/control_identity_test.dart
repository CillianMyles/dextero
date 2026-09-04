import 'dart:convert';
import 'dart:io';

import 'package:dextero_core/dextero_core.dart';
import 'package:test/test.dart';

void main() {
  test(
    'rejects an identity registry inside the controlled workspace',
    () async {
      final workspace = await Directory.systemTemp.createTemp(
        'dextero-contained-state-',
      );
      addTearDown(() => workspace.delete(recursive: true));
      final stateDirectory = Directory('${workspace.path}/.dextero-state');

      await expectLater(
        LocalIdentityRegistry(
          stateFile: File('${stateDirectory.path}/identities.json'),
        ).resolve(workspace.path),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            contains('outside the controlled workspace'),
          ),
        ),
      );
      expect(await stateDirectory.exists(), isFalse);
    },
  );

  test('rejects a symlinked registry entry inside the workspace', () async {
    if (Platform.isWindows) return;
    final sandbox = await Directory.systemTemp.createTemp(
      'dextero-symlinked-contained-state-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final workspace = await Directory('${sandbox.path}/workspace').create();
    final stateDirectory = await Directory(
      '${workspace.path}/.dextero-state',
    ).create();
    final outsideState = await File('${sandbox.path}/outside-identities.json')
        .writeAsString(
          '{"version":1,"projects":{},"workspaces":{},"checkoutOwners":{}}',
        );
    final stateLink = Link('${stateDirectory.path}/identities.json');
    await stateLink.create(outsideState.path);

    await expectLater(
      LocalIdentityRegistry(
        stateFile: File(stateLink.path),
      ).resolve(workspace.path),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          contains('outside the controlled workspace'),
        ),
      ),
    );
    expect(
      await FileSystemEntity.type(stateLink.path, followLinks: false),
      FileSystemEntityType.link,
    );
    expect(
      await outsideState.readAsString(),
      '{"version":1,"projects":{},"workspaces":{},"checkoutOwners":{}}',
    );
  });

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

  for (final metacharacter in Platform.isWindows ? ['#'] : ['#', '?']) {
    test(
      'treats $metacharacter in a relative gitdir as a literal path',
      () async {
        final sandbox = await Directory.systemTemp.createTemp(
          'dextero-relative-gitdir-',
        );
        addTearDown(() => sandbox.delete(recursive: true));
        final project = await Directory('${sandbox.path}/project').create();
        final commonGit = await Directory('${project.path}/.git').create();
        final worktree = await Directory('${sandbox.path}/feature').create();
        final checkoutName = 'sub${metacharacter}x';
        final worktreeGit = await Directory(
          '${commonGit.path}/worktrees/$checkoutName',
        ).create(recursive: true);
        await File(
          '${worktree.path}/.git',
        ).writeAsString('gitdir: ../project/.git/worktrees/$checkoutName\n');
        await File('${worktreeGit.path}/commondir').writeAsString('../..\n');
        await File(
          '${worktreeGit.path}/gitdir',
        ).writeAsString('${worktree.path}/.git\n');
        final registry = LocalIdentityRegistry(
          stateFile: File('${sandbox.path}/state/identities.json'),
          identifiers: _SequenceIdentifiers(),
        );

        final feature = await registry.resolve(worktree.path);
        final primary = await registry.resolve(project.path);

        expect(feature.projectId, primary.projectId);
        expect(feature.workspaceId, isNot(primary.workspaceId));
      },
    );
  }

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

  test('rejects a forged Git common directory', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'dextero-forged-commondir-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final victim = await Directory('${sandbox.path}/victim').create();
    final victimGit = await Directory('${victim.path}/.git').create();
    final forged = await Directory('${sandbox.path}/forged').create();
    final forgedGit = await Directory('${sandbox.path}/admin').create();
    await File(
      '${forged.path}/.git',
    ).writeAsString('gitdir: ${forgedGit.path}\n');
    await File(
      '${forgedGit.path}/gitdir',
    ).writeAsString('${forged.path}/.git\n');
    await File(
      '${forgedGit.path}/commondir',
    ).writeAsString('${victimGit.path}\n');

    await expectLater(
      LocalIdentityRegistry(
        stateFile: File('${sandbox.path}/state/identities.json'),
      ).resolve(forged.path),
      throwsA(isA<FormatException>()),
    );
    expect(
      File('${victimGit.path}/dextero-project-identity-v1').existsSync(),
      isFalse,
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

  test('does not follow marker lock symlinks from Git metadata', () async {
    if (Platform.isWindows) return;
    final sandbox = await Directory.systemTemp.createTemp(
      'dextero-symbolic-marker-lock-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final workspace = await Directory('${sandbox.path}/workspace').create();
    final gitDirectory = await Directory('${workspace.path}/.git').create();
    final outside = File('${sandbox.path}/outside-lock');
    final lockLink = Link(
      '${gitDirectory.path}/dextero-project-identity-v1.lock',
    );
    await lockLink.create(outside.path);

    final identity = await LocalIdentityRegistry(
      stateFile: File('${sandbox.path}/state/identities.json'),
      identifiers: _SequenceIdentifiers(),
    ).resolve(workspace.path);

    expect(identity.projectId, startsWith('project_'));
    expect(await outside.exists(), isFalse);
    expect(
      await FileSystemEntity.type(lockLink.path, followLinks: false),
      FileSystemEntityType.link,
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

  test('does not resolve Git from the controlled workspace', () async {
    if (Platform.isWindows) return;
    final sandbox = await Directory.systemTemp.createTemp(
      'dextero-untrusted-git-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final workspace = Directory('${sandbox.path}/workspace');
    final gitDirectory = Directory('${sandbox.path}/metadata');
    final initialized = await Process.run('/usr/bin/git', [
      'init',
      '--quiet',
      '--separate-git-dir',
      gitDirectory.path,
      workspace.path,
    ]);
    expect(initialized.exitCode, 0, reason: initialized.stderr as String);
    final marker = File('${sandbox.path}/fake-git-ran');
    final fakeGit = File('${workspace.path}/git');
    await fakeGit.writeAsString(
      '#!/bin/sh\n/usr/bin/touch "\$DEXTERO_FAKE_GIT_MARKER"\nexit 1\n',
    );
    final chmod = await Process.run('/bin/chmod', ['+x', fakeGit.path]);
    expect(chmod.exitCode, 0, reason: chmod.stderr as String);
    final helper = File(
      '${Directory.current.path}/test/fixtures/resolve_host_identity.dart',
    );

    final result = await Process.run(
      Platform.resolvedExecutable,
      [helper.path, '${sandbox.path}/state/identities.json', workspace.path],
      workingDirectory: Directory.current.path,
      includeParentEnvironment: false,
      environment: {
        'PATH': workspace.path,
        'DEXTERO_FAKE_GIT_MARKER': marker.path,
      },
    );

    expect(result.exitCode, 0, reason: result.stderr as String);
    expect(await marker.exists(), isFalse);
  });

  test('ignores inherited Git directory overrides', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'dextero-git-overrides-',
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
    final unrelated = await Directory('${sandbox.path}/unrelated').create();
    final helper = File(
      '${Directory.current.path}/test/fixtures/resolve_host_identity.dart',
    );

    final result = await Process.run(
      Platform.resolvedExecutable,
      [helper.path, '${sandbox.path}/state/identities.json', workspace.path],
      workingDirectory: Directory.current.path,
      environment: {
        'GIT_DIR': '${unrelated.path}/.git',
        'GIT_WORK_TREE': unrelated.path,
      },
    );

    expect(result.exitCode, 0, reason: result.stderr as String);
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

  test('does not reuse a recreated nested Git workspace', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'dextero-recreated-nested-workspace-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final project = await Directory('${sandbox.path}/project').create();
    await Directory('${project.path}/.git').create();
    final workspace = await Directory('${project.path}/workspace').create();
    final registry = LocalIdentityRegistry(
      stateFile: File('${sandbox.path}/state/identities.json'),
      identifiers: _SequenceIdentifiers(),
    );

    final first = await registry.resolve(workspace.path);
    await workspace.delete(recursive: true);
    await workspace.create();
    final replacement = await registry.resolve(workspace.path);

    expect(replacement.projectId, first.projectId);
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

  test('distinguishes Windows directories with matching timestamps', () async {
    if (!Platform.isWindows) return;
    final sandbox = await Directory.systemTemp.createTemp(
      'dextero-windows-file-id-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final firstDirectory = await Directory('${sandbox.path}/first').create();
    final secondDirectory = await Directory('${sandbox.path}/second').create();
    final timestamp = DateTime.utc(2025);
    final timestampResult = await Process.run(
      'powershell.exe',
      [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r'[IO.Directory]::SetCreationTimeUtc('
            r'$env:DEXTERO_FIRST_PATH, [DateTime]::Parse('
            r'$env:DEXTERO_TIMESTAMP)); '
            r'[IO.Directory]::SetCreationTimeUtc('
            r'$env:DEXTERO_SECOND_PATH, [DateTime]::Parse('
            r'$env:DEXTERO_TIMESTAMP))',
      ],
      environment: {
        'DEXTERO_FIRST_PATH': firstDirectory.path,
        'DEXTERO_SECOND_PATH': secondDirectory.path,
        'DEXTERO_TIMESTAMP': timestamp.toIso8601String(),
      },
    );
    expect(
      timestampResult.exitCode,
      0,
      reason: timestampResult.stderr as String,
    );
    final registry = LocalIdentityRegistry(
      stateFile: File('${sandbox.path}/state/identities.json'),
      identifiers: _SequenceIdentifiers(),
    );

    final first = await registry.resolve(firstDirectory.path);
    final second = await registry.resolve(secondDirectory.path);

    expect(second.projectId, isNot(first.projectId));
    expect(second.workspaceId, isNot(first.workspaceId));
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
