import 'dart:io';

import 'trusted_executable.dart';

/// Returns a host-observed identity for the current filesystem object.
Future<String> resolveFilesystemIdentity(Directory directory) async {
  late final String executable;
  late final List<String> arguments;
  if (Platform.isMacOS) {
    executable = await resolveTrustedExecutable(directory, const [
      '/usr/bin/stat',
    ]);
    arguments = ['-f', '%d:%i:%B', directory.path];
  } else if (Platform.isLinux) {
    executable = await resolveTrustedExecutable(directory, const [
      '/usr/bin/stat',
      '/bin/stat',
    ]);
    // `%w` retains sub-second birth-time precision, unlike integer `%W`.
    arguments = ['-c', '%d:%i:%w', directory.path];
  } else if (Platform.isWindows) {
    final systemRoot = operatingSystemEnvironmentValue('SYSTEMROOT');
    if (systemRoot == null) {
      throw FileSystemException(
        'Cannot locate the trusted Windows system directory',
        directory.path,
      );
    }
    executable = await resolveTrustedExecutable(directory, [
      '$systemRoot\\System32\\WindowsPowerShell\\v1.0\\powershell.exe',
    ]);
    arguments = [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      windowsFileIdentityScript,
    ];
  } else {
    throw UnsupportedError(
      'Stable workspace identity is unsupported on '
      '${Platform.operatingSystem}.',
    );
  }

  final result = await Process.run(
    executable,
    arguments,
    includeParentEnvironment: false,
    environment: Platform.isWindows
        ? _windowsIdentityEnvironment(directory.path)
        : Platform.isLinux
        ? const {'LC_ALL': 'C', 'TZ': 'UTC'}
        : const {'LC_ALL': 'C', 'TZ': 'UTC'},
  );
  final value = (result.stdout as String).trim();
  if (result.exitCode != 0 || value.isEmpty) {
    throw FileSystemException(
      'Cannot resolve stable filesystem identity: ${result.stderr}',
      directory.path,
    );
  }
  if (Platform.isLinux && value.endsWith(':-')) {
    throw FileSystemException(
      'Cannot resolve stable filesystem identity: filesystem birth time is '
      'unavailable',
      directory.path,
    );
  }
  return '${Platform.operatingSystem}:$value';
}

Map<String, String> _windowsIdentityEnvironment(String path) {
  final environment = {'DEXTERO_IDENTITY_PATH': path};
  for (final name in const ['SYSTEMROOT', 'TEMP', 'TMP']) {
    final value = operatingSystemEnvironmentValue(name);
    if (value != null) environment[name] = value;
  }
  return environment;
}

const windowsFileIdentityBootstrap = r'''
$source = @'
using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public static class DexteroFileIdentity
{
    private const uint FileFlagBackupSemantics = 0x02000000;

    [StructLayout(LayoutKind.Sequential)]
    private struct ByHandleFileInformation
    {
        public uint FileAttributes;
        public System.Runtime.InteropServices.ComTypes.FILETIME CreationTime;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastAccessTime;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWriteTime;
        public uint VolumeSerialNumber;
        public uint FileSizeHigh;
        public uint FileSizeLow;
        public uint NumberOfLinks;
        public uint FileIndexHigh;
        public uint FileIndexLow;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateFile(
        string fileName,
        uint desiredAccess,
        FileShare shareMode,
        IntPtr securityAttributes,
        FileMode creationDisposition,
        uint flagsAndAttributes,
        IntPtr templateFile);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetFileInformationByHandle(
        SafeFileHandle handle,
        out ByHandleFileInformation information);

    public static string Read(string path)
    {
        SafeFileHandle handle = CreateFile(
            path,
            0,
            FileShare.ReadWrite | FileShare.Delete,
            IntPtr.Zero,
            FileMode.Open,
            FileFlagBackupSemantics,
            IntPtr.Zero);
        if (handle.IsInvalid)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error());
        }

        using (handle)
        {
            ByHandleFileInformation information;
            if (!GetFileInformationByHandle(handle, out information))
            {
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }
            return information.VolumeSerialNumber.ToString("x8") + ":" +
                information.FileIndexHigh.ToString("x8") +
                information.FileIndexLow.ToString("x8");
        }
    }
}
'@
Add-Type -TypeDefinition $source | Out-Null
''';

const windowsFileIdentityScript =
    windowsFileIdentityBootstrap +
    r'''
[Console]::Out.WriteLine(
    [DexteroFileIdentity]::Read($env:DEXTERO_IDENTITY_PATH))
''';
