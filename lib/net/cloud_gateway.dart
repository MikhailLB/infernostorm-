import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../data/gate_reply.dart';
import '../env/app_config.dart';
import 'launch_bridge.dart';
import 'blaze_storage.dart';

class CloudGateway {
  final BlazeStorage _store;

  CloudGateway(this._store);

  Future<GateReply> fetch(Map<String, dynamic> payload) async {
    if (AppConfig.configEndpoint.isEmpty) {
      debugPrint('[CloudGateway] request skipped — no endpoint configured');
      return GateReply.failure('no endpoint');
    }
    try {
      final uri  = Uri.parse(AppConfig.configEndpoint);
      debugPrint('[CloudGateway] POST $uri body=${jsonEncode(payload)}');
      final resp = await httpBridge
          .post(uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(payload))
          .timeout(const Duration(seconds: 15));

      debugPrint('[CloudGateway] response status=${resp.statusCode} '
          'body=${resp.body}');

      if (resp.statusCode == 200) {
        final json   = jsonDecode(resp.body) as Map<String, dynamic>;
        final result = GateReply.fromJson(json);
        debugPrint('[CloudGateway] parsed ok=${result.ok} url=${result.url} '
            'expires=${result.expires} msg=${result.message}');
        if (result.ok && result.url != null) {
          await _store.writeUrl(result.url!);
          if (result.expires != null) await _store.setExpires(result.expires!);
        }
        return result;
      }
      return GateReply.failure('HTTP ${resp.statusCode}');
    } catch (e) {
      debugPrint('[CloudGateway] request failed: $e');
      return GateReply.failure(e.toString());
    }
  }

  Future<String?> cachedUrl() => _store.readUrl();
}
