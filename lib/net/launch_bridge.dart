import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import '../cipher/scrambler.dart';
import '../env/app_config.dart';

// Chrome/WebKit version fragments — XOR-encoded.
// Run tool/encode_keys.dart to regenerate.
String get _chromeVer => x(const <int>[
      0x6e, 0x9f, 0x47, 0x24, 0x4b, 0xb6, 0xc7, 0xee,
      0x64, 0x70, 0x03, 0x53, 0xc5, 0x83,
    ]);

String get _webkitVer => x(const <int>[
      0x6a, 0x9f, 0x42, 0x24, 0x48, 0xae,
    ]);

class LaunchBridge extends http.BaseClient {
  final _inner = http.Client();
  String? _ua;

  /// Call once in main() before runApp().
  Future<void> init() async {
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        final sdk   = a.version.sdkInt;
        final model = a.model;
        final brand = a.brand;
        final build = a.display.isNotEmpty ? a.display : a.id;
        final cv    = _chromeVer.isNotEmpty ? _chromeVer : '132.0.6834.163';
        final wk    = _webkitVer.isNotEmpty ? _webkitVer : '537.36';
        // Format per TZ: standard Chrome UA + appid + appname
        _ua = 'Mozilla/5.0 (Linux; Android $sdk; $brand $model '
            'Build/$build) AppleWebKit/$wk (KHTML, like Gecko) '
            'Chrome/$cv Mobile Safari/$wk '
            'appid/${AppConfig.bundleId} appname/${AppConfig.appName}';
      } else {
        final i   = await info.iosInfo;
        final ver = i.systemVersion.replaceAll('.', '_');
        final wk  = _webkitVer.isNotEmpty ? _webkitVer : '537.36';
        _ua = 'Mozilla/5.0 (iPhone; CPU iPhone OS $ver like Mac OS X) '
            'AppleWebKit/$wk (KHTML, like Gecko) '
            'Version/${i.systemVersion} Mobile/15E148 Safari/$wk '
            'appid/${AppConfig.bundleId} appname/${AppConfig.appName}';
      }
    } catch (_) {
      final cv = _chromeVer.isNotEmpty ? _chromeVer : '132.0.6834.163';
      final wk = _webkitVer.isNotEmpty ? _webkitVer : '537.36';
      _ua = Platform.isAndroid
          ? 'Mozilla/5.0 (Linux; Android 15; SM-S931U '
              'Build/AP3A.240905.015.A2) AppleWebKit/$wk (KHTML, like Gecko) '
              'Chrome/$cv Mobile Safari/$wk '
              'appid/${AppConfig.bundleId} appname/${AppConfig.appName}'
          : 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
              'AppleWebKit/$wk (KHTML, like Gecko) '
              'Version/17.0 Mobile/15E148 Safari/$wk '
              'appid/${AppConfig.bundleId} appname/${AppConfig.appName}';
    }
  }

  String get userAgent => _ua ?? 'Mozilla/5.0';

  @override
  Future<http.StreamedResponse> send(http.BaseRequest req) {
    req.headers.putIfAbsent('User-Agent', () => userAgent);
    return _inner.send(req);
  }

  @override
  void close() => _inner.close();
}

/// Global singleton — used by all net services.
final httpBridge = LaunchBridge();
