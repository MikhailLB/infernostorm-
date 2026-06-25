import 'dart:convert';
import '../data/gate_reply.dart';
import '../env/app_config.dart';
import 'launch_bridge.dart';
import 'blaze_storage.dart';

class CloudGateway {
  final BlazeStorage _store;

  CloudGateway(this._store);

  Future<GateReply> fetch(Map<String, dynamic> payload) async {
    if (AppConfig.configEndpoint.isEmpty) {
      return GateReply.failure('no endpoint');
    }
    try {
      final uri  = Uri.parse(AppConfig.configEndpoint);
      final resp = await httpBridge
          .post(uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(payload))
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        final json   = jsonDecode(resp.body) as Map<String, dynamic>;
        final result = GateReply.fromJson(json);
        if (result.ok && result.url != null) {
          await _store.writeUrl(result.url!);
          if (result.expires != null) await _store.setExpires(result.expires!);
        }
        return result;
      }
      return GateReply.failure('HTTP ${resp.statusCode}');
    } catch (e) {
      return GateReply.failure(e.toString());
    }
  }

  Future<String?> cachedUrl() => _store.readUrl();
}
