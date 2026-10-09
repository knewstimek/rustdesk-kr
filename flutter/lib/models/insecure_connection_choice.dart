import 'dart:convert';

const insecureConnectionConsentOption = 'kr-insecure-connection-consent';

String insecureConnectionConsentScope(
        {required String peerId,
        required String idServer,
        required String relayServer,
        required String publicKey}) =>
    jsonEncode([peerId, idServer.trim(), relayServer.trim(), publicKey.trim()]);

bool skipRememberedInsecureConnectionWarning(
        {required bool isAndroid,
        required String peerId,
        required String savedScope,
        required String currentScope}) =>
    isAndroid &&
    peerId.isNotEmpty &&
    savedScope.isNotEmpty &&
    savedScope == currentScope;
