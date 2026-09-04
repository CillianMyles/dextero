import 'package:dextero_server/dextero_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef IdentityReader = Future<String?> Function();
typedef IdentityWriter = Future<void> Function(String value);

/// Persists one stable identity for this Flutter installation.
final class AppControllerIdentityStore {
  AppControllerIdentityStore({
    required IdentityReader readId,
    required IdentityWriter writeId,
  }) : _readId = readId,
       _writeId = writeId;

  factory AppControllerIdentityStore.platform() {
    final preferences = SharedPreferencesAsync();
    return AppControllerIdentityStore(
      readId: () => preferences.getString(_preferenceKey),
      writeId: (value) => preferences.setString(_preferenceKey, value),
    );
  }

  static const _preferenceKey = 'dextero.controller-id.v1';

  final IdentityReader _readId;
  final IdentityWriter _writeId;

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
  }
}
