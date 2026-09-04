import 'dart:math';

/// Creates and validates self-asserted controller identities.
///
/// These identifiers provide stable attribution. They do not replace the
/// bootstrap token or provide cryptographic device pairing.
abstract final class ControllerIdentities {
  static final RegExp _idPattern = RegExp(
    r'^controller_[A-Za-z0-9_-]{16,128}$',
  );

  static String createId({Random? random, DateTime Function()? clock}) {
    final source = random ?? Random.secure();
    final timestamp = (clock ?? DateTime.now)()
        .toUtc()
        .microsecondsSinceEpoch
        .toRadixString(36);
    final entropy = List.generate(
      3,
      (_) => source.nextInt(0x100000000).toRadixString(36).padLeft(7, '0'),
    ).join();
    return 'controller_${timestamp}_$entropy';
  }

  static ({String id, String name}) validated({
    required String id,
    required String name,
  }) {
    id = id.trim();
    name = name.trim();
    if (!_idPattern.hasMatch(id)) {
      throw ArgumentError.value(
        id,
        'controller.id',
        'must be a stable controller identifier',
      );
    }
    if (name.isEmpty ||
        name.length > 120 ||
        name.codeUnits.any((unit) => unit < 32 || unit == 127)) {
      throw ArgumentError.value(
        name,
        'controller.name',
        'must contain 1 to 120 printable characters',
      );
    }
    return (id: id, name: name);
  }

  static bool isValidId(String value) => _idPattern.hasMatch(value.trim());
}
