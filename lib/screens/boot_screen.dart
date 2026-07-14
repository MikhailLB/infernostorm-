import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../bridge/insight.dart';
import '../data/run_mode.dart';
import '../net/blaze_storage.dart';
import '../net/cloud_gateway.dart';
import '../net/flow_controller.dart';
import '../net/net_probe.dart';
import '../net/signal_service.dart';
import 'alert_opt_in.dart';
import 'menu_screen.dart';
import 'offline_wall.dart';
import 'gate_screen.dart' deferred as gate;

// ── Progress stages ───────────────────────────────────────────
enum _Stage { empty, mid, done }

class BootScreen extends StatefulWidget {
  final BlazeStorage storage;
  final NetProbe probe;
  final FlowController flow;
  final CloudGateway gateway;
  final SignalService signal;

  const BootScreen({
    super.key,
    required this.storage,
    required this.probe,
    required this.flow,
    required this.gateway,
    required this.signal,
  });

  @override
  State<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<BootScreen> {
  double _progress = 0.0;
  int _dots = 0;
  late AnimationController _progressCtrl;
  late Timer _dotTimer;
  _Stage _stage = _Stage.empty;
  bool _routed = false;

  @override
  void initState() {
    super.initState();
    Insight.screen('loading');
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Smooth progress bar — pauses at 0.6 until routing is done,
    // then completes on navigate.
    _progressCtrl = AnimationController(
      vsync: Navigator.of(context),
      duration: const Duration(milliseconds: 3500),
    );
    _progressCtrl.addListener(() {
      if (!mounted) return;
      final v = _progressCtrl.value;
      // Clamp to 0.6 until we have a routing decision
      setState(() => _progress = (_stage == _Stage.done) ? v : v.clamp(0.0, 0.6));
    });

    _dotTimer =
        Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() => _dots = (_dots + 1) % 4);
    });

    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _progressCtrl.forward();
    });

    widget.signal.onTokenRotated = _onTokenRotated;
    _boot();
  }

  @override
  void dispose() {
    widget.signal.onTokenRotated = null;
    _progressCtrl.dispose();
    _dotTimer.cancel();
    super.dispose();
  }

  // ── Token refresh ─────────────────────────────────────────────

  void _onTokenRotated(String newToken) async {
    final locale = Platform.localeName.replaceAll('-', '_');
    final body = await widget.flow.buildPayload(
      locale: locale,
      pushToken: newToken,
    );
    widget.gateway.fetch(body);
  }

  // ── Boot routing ──────────────────────────────────────────────

  Future<void> _boot() async {
    await widget.signal.init().catchError((_) {});

    final mode = widget.storage.getMode();
    switch (mode) {
      case RunMode.online:
        await _handleOnline();
      case RunMode.offline:
        await _handleOfflineReturn();
      case RunMode.pending:
        await _handleFirstRun();
    }
  }

  Future<void> _handleFirstRun() async {
    final online = await widget.probe.isOnline();
    if (!online) {
      Insight.event('route_offline');
      if (!mounted) return;
      _route(() => OfflineWall(onRetry: (_) => _rebuildBoot()));
      return;
    }

    _setStage(_Stage.mid);
    await widget.flow.init();
    await Future.wait([
      widget.flow.awaitAttribution(),
      widget.flow.awaitDeepLink(),
    ]);

    final locale = Platform.localeName.replaceAll('-', '_');
    final body = await widget.flow.buildPayload(
      locale: locale,
      pushToken: widget.signal.token,
    );
    _identifyFromPayload(body);
    final reply = await widget.gateway.fetch(body);

    _setStage(_Stage.done);
    await Future.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;

    if (reply.ok && reply.url != null) {
      await widget.storage.setMode(RunMode.online);
      Insight.tag('run_mode', 'web');
      Insight.event('route_web');
      _goContent(reply.url!);
    } else {
      await widget.storage.setMode(RunMode.offline);
      Insight.tag('run_mode', 'native');
      Insight.event('route_native');
      _route(() => const MenuScreen());
    }
  }

  Future<void> _handleOnline() async {
    final online = await widget.probe.isOnline();
    if (!online) {
      Insight.event('route_offline');
      _setStage(_Stage.done);
      if (!mounted) return;
      _route(() => OfflineWall(onRetry: (_) => _rebuildBoot()));
      return;
    }

    // Push URL takes priority
    final pushUrl = await widget.storage.consumePushUrl();
    if (pushUrl != null) {
      Insight.tag('run_mode', 'web');
      Insight.event('route_push_link');
      _setStage(_Stage.done);
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      _goContent(pushUrl);
      return;
    }

    final savedUrl = await widget.gateway.cachedUrl();

    _setStage(_Stage.mid);
    await widget.flow.init();
    await Future.wait([
      widget.flow
          .awaitAttribution()
          .timeout(const Duration(seconds: 10), onTimeout: () => {}),
      widget.flow.awaitDeepLink(),
    ]);

    final locale = Platform.localeName.replaceAll('-', '_');
    final body = await widget.flow.buildPayload(
      locale: locale,
      pushToken: widget.signal.token,
    );
    _identifyFromPayload(body);
    final reply = await widget.gateway.fetch(body);

    _setStage(_Stage.done);
    await Future.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;

    if (reply.ok && reply.url != null) {
      Insight.tag('run_mode', 'web');
      Insight.event('route_web');
      _goContent(reply.url!);
    } else if (savedUrl != null) {
      Insight.tag('run_mode', 'web');
      Insight.event('route_cached_link');
      _goContent(savedUrl);
    } else {
      Insight.event('route_offline');
      _route(() => OfflineWall(onRetry: (_) => _rebuildBoot()));
    }
  }

  Future<void> _handleOfflineReturn() async {
    _setStage(_Stage.mid);

    // Attempt gateway recovery: on the first-run the network / attribution
    // might have been unavailable, which pinned us into offline mode forever.
    // If we now have connectivity, retry once — a successful reply upgrades
    // us back to online (gray-part). Otherwise fall through to MenuScreen.
    final online = await widget.probe.isOnline();
    if (online) {
      try {
        await widget.flow.init();
        await Future.wait([
          widget.flow
              .awaitAttribution()
              .timeout(const Duration(seconds: 8), onTimeout: () => {}),
          widget.flow
              .awaitDeepLink()
              .timeout(const Duration(seconds: 4), onTimeout: () => {}),
        ]);

        final locale = Platform.localeName.replaceAll('-', '_');
        final body = await widget.flow.buildPayload(
          locale: locale,
          pushToken: widget.signal.token,
        );
        _identifyFromPayload(body);
        final reply = await widget.gateway.fetch(body);

        if (reply.ok && reply.url != null) {
          await widget.storage.setMode(RunMode.online);
          Insight.tag('run_mode', 'web');
          Insight.event('route_web');
          _setStage(_Stage.done);
          await Future.delayed(const Duration(milliseconds: 350));
          if (!mounted) return;
          _goContent(reply.url!);
          return;
        }
      } catch (_) {
        // Recovery failed — silently continue to MenuScreen.
      }
    }

    Insight.tag('run_mode', 'native');
    Insight.event('route_native');

    await Future.delayed(const Duration(milliseconds: 300));
    _setStage(_Stage.done);
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    _route(() => const MenuScreen());
  }

  /// Extracts af_id + attribution tags from the gateway payload and
  /// forwards them to Insight so every session is groupable by user.
  void _identifyFromPayload(Map<String, dynamic> body) {
    Insight.identify(
      body['af_id']?.toString(),
      tags: {
        'af_status': body['af_status']?.toString() ?? '',
        'media_source': body['media_source']?.toString() ?? '',
        'campaign': body['campaign']?.toString() ?? '',
        'os': body['os']?.toString() ?? '',
        'locale': body['locale']?.toString() ?? '',
      },
    );
  }

  Future<void> _goContent(String url) async {
    await gate.loadLibrary();
    if (!mounted) return;
    final Widget next;
    if (widget.storage.shouldShowNotifScreen()) {
      next = AlertOptIn(
        storage: widget.storage,
        signal: widget.signal,
        probe: widget.probe,
        targetUrl: url,
      );
    } else {
      // Returning user: no invite this run — classify the notif state so
      // the `notif_permission` tag is never empty in the dashboard.
      Insight.tag(
        'notif_permission',
        widget.storage.isNotifGranted()
            ? 'granted'
            : widget.storage.isNotifOsDenied()
                ? 'os_denied'
                : 'snoozed',
      );
      next = gate.GateScreen(
        url: url,
        storage: widget.storage,
        signal: widget.signal,
        probe: widget.probe,
      );
    }
    _route(() => next);
  }

  void _route(Widget Function() builder) {
    if (_routed) return;
    _routed = true;
    // Lock to portrait for game/menu; GateScreen unlocks itself
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => builder(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  BootScreen _rebuildBoot() => BootScreen(
        storage: widget.storage,
        probe: widget.probe,
        flow: widget.flow,
        gateway: widget.gateway,
        signal: widget.signal,
      );

  void _setStage(_Stage s) {
    if (mounted) setState(() => _stage = s);
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return OrientationBuilder(builder: (ctx, orientation) {
      final isLand = orientation == Orientation.landscape;
      final bg = isLand
          ? 'assets/Horizontal_LoadingScreen.webp'
          : 'assets/Vertical_LoadingScreen.webp';
      final dotStr = '.${'.' * _dots}';

      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(bg, fit: BoxFit.cover),

            // Darkening gradient at bottom for readability
            Positioned(
              left: 0, right: 0, bottom: 0,
              height: MediaQuery.of(ctx).size.height * 0.3,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.75),
                    ],
                  ),
                ),
              ),
            ),

            // Progress bar + Loading text
            Positioned(
              left: MediaQuery.of(ctx).size.width * 0.07,
              right: MediaQuery.of(ctx).size.width * 0.07,
              bottom: isLand
                  ? MediaQuery.of(ctx).size.height * 0.08
                  : MediaQuery.of(ctx).size.height * 0.09,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Loading$dotStr',
                    style: TextStyle(
                      color: Colors.orange.shade100,
                      fontSize: isLand ? 22 : 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.0,
                      shadows: const [
                        Shadow(
                            color: Colors.black,
                            offset: Offset(2, 2),
                            blurRadius: 6),
                        Shadow(
                            color: Colors.deepOrange,
                            offset: Offset(0, 0),
                            blurRadius: 12),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _ProgressBar(value: _progress),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _ProgressBar extends StatelessWidget {
  final double value;
  const _ProgressBar({required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 16,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Colors.black.withValues(alpha: 0.55),
        border: Border.all(color: Colors.orange.shade700, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withValues(alpha: 0.35),
            blurRadius: 10, spreadRadius: 1,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: value,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.orange.shade900,
                  Colors.orange.shade500,
                  Colors.yellow.shade600,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.orange.withValues(alpha: 0.7),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
