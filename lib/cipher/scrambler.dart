import 'dart:typed_data';

// Seed: "infrnst" — unique to InfernoStorm.
// DO NOT copy seed to other projects.
// Run tool/encode_keys.dart after changing this seed.
Uint8List _buildKey() {
  const parts = <int>[
    0x69, 0x6E, 0x66, 0x72, 0x6E, 0x73, 0x74, // infrnst
  ];

  final seed = parts.fold<int>(0, (a, b) => (a * 31 + b) & 0xFFFFFFFF);
  final key = Uint8List(16);
  var v = seed;
  for (var i = 0; i < key.length; i++) {
    v = (v * 1103515245 + 12345) & 0x7FFFFFFF;
    key[i] = v & 0xFF;
  }
  return key;
}

final _k = _buildKey();

/// Decode XOR-encoded byte list back to plain string.
String x(List<int> data) {
  final out = Uint8List(data.length);
  for (var i = 0; i < data.length; i++) {
    out[i] = data[i] ^ _k[i % _k.length];
  }
  return String.fromCharCodes(out);
}
