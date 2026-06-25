enum RunMode {
  online,
  offline,
  pending;

  static RunMode fromTag(String? tag) => switch (tag) {
    'online'  => RunMode.online,
    'offline' => RunMode.offline,
    _         => RunMode.pending,
  };

  String get tag => name; // 'online' | 'offline' | 'pending'
}
