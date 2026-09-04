import 'package:dextero_server/dextero_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'controller_identity_synchronizer.dart';
import 'controller_identity_synchronizer_factory.dart';

typedef IdentityReader = Future<String?> Function();
typedef IdentityWriter = Future<void> Function(String value);

/// Persists one stable identity for this Flutter installation.
final class AppControllerIdentityStore {
  AppControllerIdentityStore({
    required IdentityReader readId,
    required IdentityWriter writeId,
    IdentitySynchronizer? synchronizer,
  }) : _readId = readId,
       _writeId = writeId,
       _synchronizer = synchronizer ?? InProcessIdentitySynchronizer.shared;

  factory AppControllerIdentityStore.platform() {
    final preferences = SharedPreferencesAsync();
    return AppControllerIdentityStore(
      readId: () => preferences.getString(_preferenceKey),
      writeId: (value) => preferences.setString(_preferenceKey, value),
      synchronizer: createControllerIdentitySynchronizer(),
    );
  }

  static const _preferenceKey = 'dextero.controller-id.v1';

  final IdentityReader _readId;
  final IdentityWriter _writeId;
  final IdentitySynchronizer _synchronizer;

  Future<ControllerIdentity> load(Map<String, String> environment) async {
    final name = environment['DEXTERO_CONTROLLER_NAME']?.trim();
    final effectiveName = name == null || name.isEmpty ? 'Dextero app' : name;
    final override = environment['DEXTERO_CONTROLLER_ID']?.trim();
    if (override != null && override.isNotEmpty) {
      final validated = ControllerIdentities.validated(
        id: override,
        name: effectiveName,
      );
      return ControllerIdentity(id: validated.id, name: validated.name);
    }

    return _synchronizer.run(() async {
      final stored = await _readId();
      if (stored != null) {
        final validated = ControllerIdentities.validated(
          id: stored,
          name: effectiveName,
        );
        return ControllerIdentity(id: validated.id, name: validated.name);
      }

      final id = ControllerIdentities.createId();
      await _writeId(id);
      return ControllerIdentity(id: id, name: effectiveName);
    });
  }
}
