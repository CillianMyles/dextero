import 'dart:convert';
import 'dart:io';

import 'filesystem_identity.dart';

/// Pins a workspace to one canonical filesystem object for an agent lifetime.
final class WorkspaceBoundary {
  const WorkspaceBoundary._({required this.root, required String identity})
    : _identity = identity;

  static Future<WorkspaceBoundary> capture(String workspace) async {
    final directory = Directory(workspace).absolute;
    if (!await directory.exists()) {
      throw ArgumentError.value(
        workspace,
        'workspace',
        'must be an existing directory',
      );
    }
    final root = await directory.resolveSymbolicLinks();
    return WorkspaceBoundary._(
      root: root,
      identity: await resolveFilesystemIdentity(Directory(root)),
    );
  }

  final String root;
  final String _identity;

  Future<void> validate() async {
    try {
      final directory = Directory(root);
      if (await directory.resolveSymbolicLinks() != root ||
          await resolveFilesystemIdentity(directory) != _identity) {
        throw const _WorkspaceChanged();
      }
    } on Object {
      throw FileSystemException(
        'Configured workspace changed after identity resolution',
        root,
      );
    }
  }

  /// Starts a child only after it verifies the filesystem-bound working dir.
  Future<Process> startProcess(
    String executable,
    List<String> arguments, {
    required Map<String, String> environment,
  }) async {
    await validate();
    final guardedEnvironment = {
      ...environment,
      'DEXTERO_EXPECTED_WORKSPACE_IDENTITY': _identity,
    };
    if (Platform.isWindows) {
      guardedEnvironment.addAll({
        'DEXTERO_GUARDED_COMMAND': executable,
        'DEXTERO_GUARDED_ARGUMENTS': jsonEncode(arguments),
      });
      return Process.start(
        'powershell.exe',
        [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          _windowsGuardedProcessScript,
        ],
        workingDirectory: root,
        runInShell: false,
        includeParentEnvironment: false,
        environment: guardedEnvironment,
      );
    }

    final guardScript = Platform.isMacOS
        ? _macOsGuardedProcessScript
        : _linuxGuardedProcessScript;
    return Process.start(
      '/bin/sh',
      ['-c', guardScript, 'dextero-workspace-guard', executable, ...arguments],
      workingDirectory: root,
      runInShell: false,
      includeParentEnvironment: false,
      environment: guardedEnvironment,
    );
  }
}

final class _WorkspaceChanged implements Exception {
  const _WorkspaceChanged();
}

const _macOsGuardedProcessScript = r'''
actual="$(/usr/bin/stat -f '%d:%i:%B' .)" || exit 126
if [ "macos:$actual" != "$DEXTERO_EXPECTED_WORKSPACE_IDENTITY" ]; then
  echo 'Configured workspace changed after identity resolution' >&2
  exit 126
fi
unset DEXTERO_EXPECTED_WORKSPACE_IDENTITY
exec "$@"
''';

const _linuxGuardedProcessScript = r'''
actual="$(stat -c '%d:%i:%w' .)" || exit 126
if [ "linux:$actual" != "$DEXTERO_EXPECTED_WORKSPACE_IDENTITY" ]; then
  echo 'Configured workspace changed after identity resolution' >&2
  exit 126
fi
unset DEXTERO_EXPECTED_WORKSPACE_IDENTITY
exec "$@"
''';

const _windowsGuardedProcessScript =
    windowsFileIdentityBootstrap +
    r'''
$actual = 'windows:' + [DexteroFileIdentity]::Read((Get-Location).Path)
if (-not [String]::Equals(
    $actual,
    $env:DEXTERO_EXPECTED_WORKSPACE_IDENTITY,
    [StringComparison]::Ordinal)) {
  [Console]::Error.WriteLine(
      'Configured workspace changed after identity resolution')
  exit 126
}
$command = (Get-Command -CommandType Application -Name $env:DEXTERO_GUARDED_COMMAND -ErrorAction Stop).Source
$commandArguments = @(
    ConvertFrom-Json -InputObject $env:DEXTERO_GUARDED_ARGUMENTS)
Remove-Item Env:DEXTERO_EXPECTED_WORKSPACE_IDENTITY
Remove-Item Env:DEXTERO_GUARDED_COMMAND
Remove-Item Env:DEXTERO_GUARDED_ARGUMENTS
& $command @commandArguments
if ($null -eq $LASTEXITCODE) { exit 0 }
exit $LASTEXITCODE
''';
