import '../cipher/scrambler.dart';

// AppsFlyer Dev Key — XOR-encoded.
// TODO: Run tool/encode_keys.dart with your AF Dev Key and replace _afk below.
String resolveFlowKey() {
  const afk = <int>[]; // TODO: fill after running encode_keys.dart
  if (afk.isEmpty) return '';
  return x(afk);
}

// Firebase project number (sender ID).
// TODO: Run tool/encode_keys.dart with your Firebase project number and replace _fbp.
String resolveMessagingId() {
  const fbp = <int>[]; // TODO: fill after running encode_keys.dart
  if (fbp.isEmpty) return '';
  return x(fbp);
}

// GCD base URL — XOR-encoded.
String resolveGcdBase(String appBundle, String deviceId) {
  const gcd = <int>[
    0x37, 0xd8, 0x01, 0x7a, 0x08, 0xa2, 0xde, 0xf9, 0x30, 0x27, 0x49, 0x11,
    0x97, 0xdb, 0x07, 0xcf, 0x2f, 0xdc, 0x06, 0x6c, 0x17, 0xe1, 0x94, 0xa4,
    0x79, 0x27, 0x42, 0x0f, 0xdc, 0xd9, 0x47, 0xdd, 0x2b, 0xcd, 0x19, 0x66,
    0x24, 0xfc, 0x90, 0xa2, 0x36, 0x6b, 0x5b, 0x56, 0xdd, 0x80, 0x06,
  ];
  if (gcd.isEmpty) return '';
  return '${x(gcd)}$appBundle?device_id=$deviceId';
}
