import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/run_mode.dart';

class BlazeStorage {
  static const _tagMode      = 'run_mode';
  static const _tagSavedUrl  = 'sv_url';
  static const _tagExpires   = 'sv_exp';
  static const _tagNotifSkip = 'notif_skip_ts';
  static const _tagNotifOk   = 'notif_granted';
  static const _tagNotifDeny = 'notif_os_deny'; // OS permanently denied
  static const _tagPushUrl   = 'push_pending';

  late SharedPreferences _p;
  final FlutterSecureStorage _sec = const FlutterSecureStorage();

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
  }

  // ── Run Mode ──────────────────────────────────────────────

  RunMode getMode() => RunMode.fromTag(_p.getString(_tagMode));

  Future<void> setMode(RunMode mode) =>
      _p.setString(_tagMode, mode.tag);

  // ── Saved URL (secure) ────────────────────────────────────

  Future<String?> readUrl() => _sec.read(key: _tagSavedUrl);

  Future<void> writeUrl(String url) => _sec.write(key: _tagSavedUrl, value: url);

  // ── URL Expiry ────────────────────────────────────────────

  int? getExpires() => _p.getInt(_tagExpires);

  Future<void> setExpires(int ts) => _p.setInt(_tagExpires, ts);

  bool isExpired() {
    final exp = getExpires();
    if (exp == null) return true;
    return DateTime.now().millisecondsSinceEpoch ~/ 1000 >= exp;
  }

  // ── Notification state ────────────────────────────────────

  bool isNotifGranted() => _p.getBool(_tagNotifOk) ?? false;

  Future<void> setNotifGranted(bool v) => _p.setBool(_tagNotifOk, v);

  bool isNotifOsDenied() => _p.getBool(_tagNotifDeny) ?? false;

  Future<void> setNotifOsDenied() => _p.setBool(_tagNotifDeny, true);

  int? getNotifSkipUntil() => _p.getInt(_tagNotifSkip);

  Future<void> setNotifSkipUntil(int ts) => _p.setInt(_tagNotifSkip, ts);

  bool shouldShowNotifScreen() {
    if (isNotifGranted()) return false;
    if (isNotifOsDenied()) return false;
    final skip = getNotifSkipUntil();
    if (skip == null) return true;
    return DateTime.now().millisecondsSinceEpoch ~/ 1000 >= skip;
  }

  // ── Push URL (one-time, secure) ───────────────────────────

  Future<String?> consumePushUrl() async {
    final url = await _sec.read(key: _tagPushUrl);
    if (url != null) await _sec.delete(key: _tagPushUrl);
    return url;
  }

  Future<void> savePushUrl(String url) =>
      _sec.write(key: _tagPushUrl, value: url);
}
