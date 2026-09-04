import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'controller_identity_synchronizer.dart';

IdentitySynchronizer createControllerIdentitySynchronizer() =>
    const _WebIdentitySynchronizer();

final class _WebIdentitySynchronizer implements IdentitySynchronizer {
  const _WebIdentitySynchronizer();

  static const _lockName = 'dextero-app-controller-identity-v1';

  @override
  Future<T> run<T>(Future<T> Function() action) async {
    late T result;
    Object? actionError;
    StackTrace? actionStackTrace;
    final callback = ((web.Lock _) {
      return (() async {
        try {
          result = await action();
        } on Object catch (error, stackTrace) {
          actionError = error;
          actionStackTrace = stackTrace;
        }
      })().toJS;
    }).toJS;

    await web.window.navigator.locks.request(_lockName, callback).toDart;
    if (actionError != null) {
      Error.throwWithStackTrace(actionError!, actionStackTrace!);
    }
    return result;
  }
}
