import 'package:clarity_flutter/clarity_flutter.dart';
import '../env/insight_env.dart';

/// Crash-safe facade over Microsoft Clarity.
///
/// Session replay captures the native Flutter surface (loading screen,
/// push-invite screen, menu, game, and the WebView container). The DOM
/// inside the WebView is NOT recorded — the funnel signals below add
/// custom events / tags so we can still answer "where did the user drop
/// off?" from the dashboard.
///
/// Every entry point is wrapped in [_guard] so a Clarity failure can
/// never bubble up and break the app flow.
class Insight {
  const Insight._();

  /// Shared config. `Verbose` while wiring a new project, `None` in release
  /// so logcat is not spammed by SDK internals.
  static ClarityConfig get config => ClarityConfig(
        projectId: kClarityProjectId,
        logLevel: LogLevel.None,
      );

  /// Groups the session under an AppsFlyer id and attaches attribution tags.
  /// No-op on empty id so a missing af_id never wipes a good user id.
  static void identify(String? aid, {Map<String, String> tags = const {}}) {
    if (aid != null && aid.isNotEmpty) {
      _guard(() => Clarity.setCustomUserId(_clip(aid, 255)));
      tag('aid', aid);
    }
    tags.forEach(tag);
  }

  /// Native screen entry point: sets the label AND emits a stable
  /// per-screen event (`screen_<name>`).
  static void screen(String name) {
    screenName(name);
    event('screen_$name');
  }

  /// Sets the current screen label + mirrors it into the persistent
  /// `last_screen` tag. Clarity keeps the LAST tag value per session, so
  /// filtering by `last_screen` instantly shows the drop-off screen.
  static void screenName(String name) => _guard(() {
        Clarity.setCurrentScreenName(_clip(name, 255));
        Clarity.setCustomTag('last_screen', _clip(name, 255));
      });

  static void event(String name) =>
      _guard(() => Clarity.sendCustomEvent(_clip(name, 254)));

  static void tag(String key, String value) {
    if (value.isEmpty) return;
    _guard(() => Clarity.setCustomTag(key, _clip(value, 255)));
  }

  static String _clip(String v, int max) =>
      v.length <= max ? v : v.substring(0, max);

  static void _guard(void Function() body) {
    try {
      body();
    } catch (_) {}
  }
}
