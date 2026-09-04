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
    _windowsProcessLauncherBootstrap +
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
$exitCode = [DexteroProcessLauncher]::Run(
    $command,
    [string[]] $commandArguments,
    (Get-Location).Path)
exit $exitCode
''';

const _windowsProcessLauncherBootstrap = r'''
$launcherSource = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Text;

public static class DexteroProcessLauncher
{
    public static int Run(
        string executable,
        string[] arguments,
        string workingDirectory)
    {
        ProcessStartInfo startInfo = new ProcessStartInfo();
        startInfo.FileName = executable;
        startInfo.Arguments = JoinArguments(arguments);
        startInfo.WorkingDirectory = workingDirectory;
        startInfo.UseShellExecute = false;

        using (Process process = Process.Start(startInfo))
        {
            process.WaitForExit();
            return process.ExitCode;
        }
    }

    private static string JoinArguments(string[] arguments)
    {
        List<string> quoted = new List<string>();
        foreach (string argument in arguments)
        {
            quoted.Add(QuoteArgument(argument));
        }
        return String.Join(" ", quoted.ToArray());
    }

    // Match the Windows CommandLineToArgvW/CRT escaping convention used by
    // direct process launchers, including empty values and trailing slashes.
    private static string QuoteArgument(string argument)
    {
        bool needsQuotes = argument.Length == 0;
        foreach (char character in argument)
        {
            if (Char.IsWhiteSpace(character) || character == '"')
            {
                needsQuotes = true;
                break;
            }
        }
        if (!needsQuotes)
        {
            return argument;
        }

        StringBuilder result = new StringBuilder();
        result.Append('"');
        int slashes = 0;
        foreach (char character in argument)
        {
            if (character == '\\')
            {
                slashes++;
                continue;
            }
            if (character == '"')
            {
                result.Append('\\', slashes * 2 + 1);
                result.Append('"');
                slashes = 0;
                continue;
            }
            result.Append('\\', slashes);
            result.Append(character);
            slashes = 0;
        }
        result.Append('\\', slashes * 2);
        result.Append('"');
        return result.ToString();
    }
}
'@
Add-Type -TypeDefinition $launcherSource | Out-Null
''';
