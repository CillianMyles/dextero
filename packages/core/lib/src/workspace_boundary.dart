import 'dart:convert';
import 'dart:io';

import 'control_identity.dart';
import 'filesystem_identity.dart';

/// Pins a workspace to one canonical filesystem object for an agent lifetime.
final class WorkspaceBoundary {
  const WorkspaceBoundary._({
    required this.root,
    required String identity,
    required String repositoryTopologyIdentity,
  }) : _identity = identity,
       _repositoryTopologyIdentity = repositoryTopologyIdentity;

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
    final boundary = WorkspaceBoundary._(
      root: root,
      identity: await resolveFilesystemIdentity(Directory(root)),
      repositoryTopologyIdentity: await resolveRepositoryTopologyIdentity(
        Directory(root),
      ),
    );
    await boundary.validate();
    return boundary;
  }

  final String root;
  final String _identity;
  final String _repositoryTopologyIdentity;

  Future<void> validate() async {
    try {
      final directory = Directory(root);
      if (await directory.resolveSymbolicLinks() != root ||
          await resolveFilesystemIdentity(directory) != _identity ||
          await resolveRepositoryTopologyIdentity(directory) !=
              _repositoryTopologyIdentity) {
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
        'DEXTERO_GUARDED_ARGUMENTS': base64Encode(
          utf8.encode(_windowsArgumentLine(arguments)),
        ),
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
actual="$(LC_ALL=C TZ=UTC stat -c '%d:%i:%w' .)" || exit 126
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
$commandArguments = [Text.Encoding]::UTF8.GetString(
    [Convert]::FromBase64String($env:DEXTERO_GUARDED_ARGUMENTS))
Remove-Item Env:DEXTERO_EXPECTED_WORKSPACE_IDENTITY
Remove-Item Env:DEXTERO_GUARDED_COMMAND
Remove-Item Env:DEXTERO_GUARDED_ARGUMENTS
$startInfo = New-Object System.Diagnostics.ProcessStartInfo
$startInfo.FileName = $command
$startInfo.Arguments = $commandArguments
$startInfo.WorkingDirectory = (Get-Location).Path
$startInfo.UseShellExecute = $false
$process = [Diagnostics.Process]::Start($startInfo)
$process.WaitForExit()
$exitCode = $process.ExitCode
$process.Dispose()
exit $exitCode
''';

String _windowsArgumentLine(List<String> arguments) =>
    arguments.map(_quoteWindowsArgument).join(' ');

String _quoteWindowsArgument(String argument) {
  if (argument.isNotEmpty && !RegExp(r'[\s"]').hasMatch(argument)) {
    return argument;
  }

  final result = StringBuffer('"');
  var slashes = 0;
  for (final unit in argument.codeUnits) {
    if (unit == 0x5c) {
      slashes++;
      continue;
    }
    if (unit == 0x22) {
      result
        ..write(r'\' * (slashes * 2 + 1))
        ..write('"');
      slashes = 0;
      continue;
    }
    result
      ..write(r'\' * slashes)
      ..writeCharCode(unit);
    slashes = 0;
  }
  result
    ..write(r'\' * (slashes * 2))
    ..write('"');
  return result.toString();
}
