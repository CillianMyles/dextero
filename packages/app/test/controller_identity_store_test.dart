import 'package:dextero_app/src/controller_identity_store.dart';
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
}
