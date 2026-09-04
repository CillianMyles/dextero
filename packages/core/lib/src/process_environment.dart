import 'dart:async';
import 'dart:io';

const _allowedEnvironmentKeys = <String>{
  'APPDATA',
  'CODEX_HOME',
  'COMSPEC',
  'HOME',
  'LANG',
  'LC_ALL',
  'LOCALAPPDATA',
  'LOGNAME',
  'PATH',
  'PATHEXT',
  'PROGRAMFILES',
  'PROGRAMFILES(X86)',
  'SHELL',
  'SYSTEMROOT',
  'TEMP',
  'TMP',
  'TMPDIR',
  'TZ',
  'USER',
};

/// A minimal inherited environment that excludes application secrets.
Map<String, String> filteredProcessEnvironment([Map<String, String>? source]) =>
    {
      for (final entry in (source ?? Platform.environment).entries)
        if (_allowedEnvironmentKeys.contains(entry.key.toUpperCase()))
          entry.key: entry.value,
    };

/// Uses an explicit Codex home only when it contains an auth record.
Map<String, String> codexProcessEnvironment([Map<String, String>? source]) {
  final environment = filteredProcessEnvironment(source);
  final codexHome = environment['CODEX_HOME'];
  if (codexHome != null &&
      !File('$codexHome${Platform.pathSeparator}auth.json').existsSync()) {
    environment.remove('CODEX_HOME');
  }
  return environment;
}

Future<void> terminateProcessTree(
  Process process, {
  Duration gracePeriod = const Duration(seconds: 2),
}) async {
  if (Platform.isWindows) {
    await Process.run(
      'taskkill',
      ['/PID', '${process.pid}', '/T', '/F'],
      runInShell: false,
      includeParentEnvironment: false,
      environment: filteredProcessEnvironment(),
    );
    return;
  }

  final descendants = await _descendantProcessIds(process.pid);
  for (final pid in descendants.reversed) {
    Process.killPid(pid, ProcessSignal.sigterm);
  }
  process.kill(ProcessSignal.sigterm);
  try {
    await process.exitCode.timeout(gracePeriod);
  } on TimeoutException {
    for (final pid in descendants.reversed) {
      Process.killPid(pid, ProcessSignal.sigkill);
    }
    process.kill(ProcessSignal.sigkill);
  }
}

Future<List<int>> _descendantProcessIds(int rootPid) async {
  final result = await Process.run(
    '/bin/ps',
    ['-axo', 'pid=,ppid='],
    runInShell: false,
    includeParentEnvironment: false,
    environment: filteredProcessEnvironment(),
  );
  final childrenByParent = <int, List<int>>{};
  for (final line in result.stdout.toString().split('\n')) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length != 2) continue;
    final pid = int.tryParse(parts[0]);
    final parentPid = int.tryParse(parts[1]);
    if (pid == null || parentPid == null) continue;
    childrenByParent.putIfAbsent(parentPid, () => []).add(pid);
  }
  final descendants = <int>[];
  void collect(int parentPid) {
    for (final childPid in childrenByParent[parentPid] ?? const <int>[]) {
      descendants.add(childPid);
      collect(childPid);
    }
  }

  collect(rootPid);
  return descendants;
}
