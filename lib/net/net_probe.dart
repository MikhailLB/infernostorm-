import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';

class NetProbe {
  final _conn = Connectivity();

  // VPN and other non-obvious interfaces count as connectivity
  static const _liveResults = {
    ConnectivityResult.wifi,
    ConnectivityResult.mobile,
    ConnectivityResult.ethernet,
    ConnectivityResult.vpn,       // VPN IS connectivity
    ConnectivityResult.bluetooth,
    ConnectivityResult.other,
  };

  Future<bool> isOnline() async {
    final results = await _conn.checkConnectivity();
    if (!results.any(_liveResults.contains)) return false;

    try {
      // 7s timeout: real "no internet" throws SocketException instantly;
      // large timeout prevents VPN latency false-negatives.
      final answer = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 7));
      return answer.isNotEmpty && answer.first.rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Stream<List<ConnectivityResult>> get statusStream =>
      _conn.onConnectivityChanged;
}
