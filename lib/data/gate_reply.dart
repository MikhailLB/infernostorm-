class GateReply {
  final bool ok;
  final String? url;
  final String? message;
  final int? expires;

  const GateReply({
    required this.ok,
    this.url,
    this.message,
    this.expires,
  });

  factory GateReply.fromJson(Map<String, dynamic> j) => GateReply(
        ok:      j['ok']      as bool?   ?? false,
        url:     j['url']     as String?,
        message: j['message'] as String?,
        expires: j['expires'] as int?,
      );

  factory GateReply.failure(String msg) => GateReply(ok: false, message: msg);
}
