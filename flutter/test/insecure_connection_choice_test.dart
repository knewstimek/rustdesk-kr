import 'package:flutter_test/flutter_test.dart';
import '../lib/models/insecure_connection_choice.dart';

void main() {
  test('Insecure warning consent is explicit and scoped to this peer and server',
      () {
    String scope(String peer, String server, String relay, String key) =>
        insecureConnectionConsentScope(
            peerId: peer, idServer: server, relayServer: relay, publicKey: key);
    final saved = scope('peer-a', 'id.example.invalid', 'relay.example.invalid', 'public-key-a');
    bool skip(String peer, String stored, String current, {bool android = true}) =>
        skipRememberedInsecureConnectionWarning(
            isAndroid: android, peerId: peer, savedScope: stored, currentScope: current);

    expect(skip('peer-a', '', saved), false);
    expect(skip('peer-a', saved, saved), true);
    expect(skip('peer-b', saved, scope('peer-b', 'id.example.invalid', 'relay.example.invalid', 'public-key-a')), false);
    expect(skip('peer-a', saved, scope('peer-a', 'other.example.invalid', 'relay.example.invalid', 'public-key-a')), false);
    expect(skip('peer-a', saved, scope('peer-a', 'id.example.invalid', 'other.example.invalid', 'public-key-a')), false);
    expect(skip('peer-a', saved, scope('peer-a', 'id.example.invalid', 'relay.example.invalid', 'public-key-b')), false);
    expect(skip('', saved, saved), false);
    expect(skip('peer-a', saved, saved, android: false), false);
  });
}
