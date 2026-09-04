import 'dart:async';

abstract interface class IdentitySynchronizer {
  Future<T> run<T>(Future<T> Function() action);
}

final class InProcessIdentitySynchronizer implements IdentitySynchronizer {
  const InProcessIdentitySynchronizer._();

  static const shared = InProcessIdentitySynchronizer._();
  static Future<void> _tail = Future.value();

  @override
  Future<T> run<T>(Future<T> Function() action) async {
    final previous = _tail;
    final completer = Completer<void>();
    _tail = completer.future;
    await previous;
    try {
      return await action();
    } finally {
      completer.complete();
    }
  }
}
