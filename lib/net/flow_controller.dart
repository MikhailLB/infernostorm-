import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import 'package:flutter/foundation.dart';
import '../env/app_config.dart';
import '../env/forge_keys.dart';
import 'launch_bridge.dart';

class FlowController {
  AppsflyerSdk? _sdk;

  Map<String, dynamic>? _attribution;
  Map<String, dynamic>? _deepLink;
  Map<String, dynamic>? _appOpenData;

  final _attrDone = Completer<Map<String, dynamic>>();
  final _dlDone = Completer<void>();

  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    _ready = true;

    final opts = AppsFlyerOptions(
      afDevKey: AppConfig.flowKey,
      appId: AppConfig.analyticsAppId,
      showDebug: kDebugMode,
      timeToWaitForATTUserAuthorization: 10,
    );
    _sdk = AppsflyerSdk(opts);

    _sdk!.onInstallConversionData((data) async {
      debugPrint('[AppsFlyer] conversion data: ${jsonEncode(data)}');
      final raw = data['payload'] as Map<String, dynamic>? ?? data;
      if (raw['af_status'] == 'Organic') {
        debugPrint('[AppsFlyer] status=Organic → GCD retry in '
            '${AppConfig.gcdRetrySeconds}s');
        await Future.delayed(Duration(seconds: AppConfig.gcdRetrySeconds));
        final retry = await _fetchGcdData();
        debugPrint('[AppsFlyer] GCD retry result: ${jsonEncode(retry)}');
        _attribution = retry ?? raw;
      } else {
        _attribution = raw;
      }
      debugPrint('[AppsFlyer] final attribution: ${jsonEncode(_attribution)}');
      if (!_attrDone.isCompleted) _attrDone.complete(_attribution!);
    });

    _sdk!.onAppOpenAttribution((data) {
      debugPrint('[AppsFlyer] app-open attribution: ${jsonEncode(data)}');
      _appOpenData = data['payload'] as Map<String, dynamic>? ?? data;
    });

    _sdk!.onDeepLinking((result) {
      debugPrint('[AppsFlyer] deep link status=${result.status} '
          'clickEvent=${jsonEncode(result.deepLink?.clickEvent)}');
      if (result.deepLink != null) {
        _deepLink = result.deepLink!.clickEvent;
      }
      if (!_dlDone.isCompleted) _dlDone.complete();
    });

    await _sdk!.initSdk(
      registerConversionDataCallback: true,
      registerOnAppOpenAttributionCallback: true,
      registerOnDeepLinkingCallback: true,
    );
  }

  Future<Map<String, dynamic>?> _fetchGcdData() async {
    try {
      final uid = await deviceId();
      if (uid == null) return null;
      final bundle =
          Platform.isIOS ? AppConfig.analyticsAppId : AppConfig.bundleId;
      final url = resolveGcdBase(bundle, uid);
      if (url.isEmpty) return null;
      final resp = await httpBridge.get(Uri.parse(url), headers: {
        'authorization': 'Bearer ${AppConfig.flowKey}'
      }).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>> awaitAttribution() => _attrDone.future
      .timeout(const Duration(seconds: 30), onTimeout: () => {});

  Future<void> awaitDeepLink() =>
      _dlDone.future.timeout(const Duration(seconds: 5), onTimeout: () {});

  Future<String?> deviceId() async {
    if (_sdk == null) return null;
    try {
      return await _sdk!.getAppsFlyerUID();
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> buildPayload({
    required String locale,
    String? pushToken,
  }) async {
    final body = <String, dynamic>{};

    body.addAll(_attribution ?? {});
    _deepLink?.forEach((k, v) => body.putIfAbsent(k, () => v));
    _appOpenData?.forEach((k, v) => body.putIfAbsent(k, () => v));

    body['af_id'] = await deviceId() ?? '';
    body['bundle_id'] = AppConfig.bundleId;
    body['os'] = Platform.isAndroid ? 'Android' : 'iOS';
    body['store_id'] = AppConfig.storeId;
    body['locale'] = locale;

    if (pushToken != null && pushToken.isNotEmpty) {
      body['push_token'] = pushToken;
    }
    if (AppConfig.messagingId.isNotEmpty) {
      body['firebase_project_id'] = AppConfig.messagingId;
    }

    debugPrint('[FlowController] payload: ${jsonEncode(body)}');
    return body;
  }
}
