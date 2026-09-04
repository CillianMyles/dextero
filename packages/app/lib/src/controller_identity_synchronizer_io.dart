import 'dart:async';
import 'dart:io';

import 'controller_identity_synchronizer.dart';

IdentitySynchronizer createControllerIdentitySynchronizer() =>
    const _IoIdentitySynchronizer();

final class _IoIdentitySynchronizer implements IdentitySynchronizer {
  const _IoIdentitySynchronizer();

  static Future<void> _tail = Future.value();

  @override
  Future<T> run<T>(Future<T> Function() action) async {
    final previous = _tail;
    final completer = Completer<void>();
    _tail = completer.future;
    await previous;
    try {
      final lockFile = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'dextero-app-controller-identity-v1.lock',
      );
      final lock = await lockFile.open(mode: FileMode.append);
      var locked = false;
      try {
        await lock.lock(FileLock.exclusive);
        locked = true;
        return await action();
      } finally {
        if (locked) await lock.unlock();
        await lock.close();
      }
    } finally {
      completer.complete();
    }
  }
}
