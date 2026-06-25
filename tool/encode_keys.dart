// Run with: dart run tool/encode_keys.dart
// ignore_for_file: avoid_print
// Uses the same LCG as lib/cipher/scrambler.dart.
// Paste the printed arrays into the corresponding env/ files.

import 'dart:typed_data';

// ── Same seed as lib/cipher/scrambler.dart ──────────────────
const _parts = <int>[
  0x69, 0x6E, 0x66, 0x72, 0x6E, 0x73, 0x74, // "infrnst"
];

Uint8List _buildKey() {
  final seed = _parts.fold<int>(0, (a, b) => (a * 31 + b) & 0xFFFFFFFF);
  final key = Uint8List(16);
  var v = seed;
  for (var i = 0; i < key.length; i++) {
    v = (v * 1103515245 + 12345) & 0x7FFFFFFF;
    key[i] = v & 0xFF;
  }
  return key;
}

List<int> encode(String plaintext) {
  final key = _buildKey();
  final bytes = plaintext.codeUnits;
  return [for (var i = 0; i < bytes.length; i++) bytes[i] ^ key[i % key.length]];
}

String fmt(List<int> bytes) =>
    bytes.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(', ');

void main() {
  // ── Fill these in with real values ──────────────────────────

  // Config endpoint (net/ gate_config.dart)
  const configUrl = 'https://infernostorm.com/config.php';

  // AppsFlyer Dev Key (env/ forge_keys.dart)
  // Get from: AppsFlyer dashboard → App Settings → Dev Key
  const afKey = 'WT7fRwZva6hSx7DCnxEkKk';

  // Firebase project number (env/ forge_keys.dart)
  // Get from: Firebase Console → Project Settings → General → Project number
  const firebaseProjectNum = ''; // TODO: fill in

  // GCD base URL (env/ forge_keys.dart)
  const gcdBase = 'https://gcdsdk.appsflyer.com/install_data/v4.0/';

  // Chrome version fragment for User-Agent (net/ launch_bridge.dart)
  const chromeVersion = '132.0.6834.163';

  // WebKit version fragment for User-Agent (net/ launch_bridge.dart)
  const webkitVersion = '537.36';

  // ── Print encoded arrays ─────────────────────────────────────
  print('// ── gate_config.dart ──');
  final urlParts = _splitUrl(configUrl);
  print('const _h = <int>[${fmt(encode(urlParts.$1))}]; // host');
  print('const _p = <int>[${fmt(encode(urlParts.$2))}]; // path');

  print('\n// ── forge_keys.dart: AF key ──');
  if (afKey.isNotEmpty) {
    print('const _afk = <int>[${fmt(encode(afKey))}];');
  } else {
    print('// TODO: fill afKey above');
  }

  print('\n// ── forge_keys.dart: Firebase project num ──');
  if (firebaseProjectNum.isNotEmpty) {
    print('const _fbp = <int>[${fmt(encode(firebaseProjectNum))}];');
  } else {
    print('// TODO: fill firebaseProjectNum above');
  }

  print('\n// ── forge_keys.dart: GCD base ──');
  print('const _gcd = <int>[${fmt(encode(gcdBase))}];');

  print('\n// ── launch_bridge.dart: Chrome version ──');
  print('const _cv = <int>[${fmt(encode(chromeVersion))}];');

  print('\n// ── launch_bridge.dart: WebKit version ──');
  print('const _sv = <int>[${fmt(encode(webkitVersion))}];');
}

(String, String) _splitUrl(String url) {
  final uri = Uri.parse(url);
  final host = '${uri.scheme}://${uri.host}';
  final path = url.substring(host.length);
  return (host, path);
}
