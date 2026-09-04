import 'package:dextero_app/src/controller_identity_store.dart';
import 'package:dextero_app/src/controller_identity_synchronizer_factory.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('creates and then reuses the app controller identity', () async {
    String? stored;
    final store = AppControllerIdentityStore(
      readId: () async => stored,
      writeId: (value) async => stored = value,
    );

    final first = await store.load(const {});
    final second = await store.load(const {});

    expect(first.id, startsWith('controller_'));
    expect(second.id, first.id);
    expect(second.name, 'Dextero app');
  });

  test('uses an explicit controller identity and display name', () async {
    final store = AppControllerIdentityStore(
      readId: () async => null,
      writeId: (_) async => fail('override must not be persisted'),
    );

    final identity = await store.load(const {
      'DEXTERO_CONTROLLER_ID': 'controller_0123456789abcdef',
      'DEXTERO_CONTROLLER_NAME': 'Living room iPad',
    });

    expect(identity.id, 'controller_0123456789abcdef');
    expect(identity.name, 'Living room iPad');
  });

  test('serializes concurrent first-run identity creation', () async {
    String? stored;
    final first = AppControllerIdentityStore(
      readId: () async => stored,
      writeId: (value) async => stored = value,
    );
    final second = AppControllerIdentityStore(
      readId: () async => stored,
      writeId: (value) async => stored = value,
    );

    final identities = await Future.wait([
      first.load(const {}),
      second.load(const {}),
    ]);

    expect(identities[1].id, identities[0].id);
  });

  test('serializes platform identity creation between clients', () async {
    if (!kIsWeb) return;
    String? stored;
    AppControllerIdentityStore store() => AppControllerIdentityStore(
      readId: () async => stored,
      writeId: (value) async => stored = value,
      synchronizer: createControllerIdentitySynchronizer(),
    );

    final identities = await Future.wait([
      store().load(const {}),
      store().load(const {}),
    ]);

    expect(identities[1].id, identities[0].id);
  });
}
