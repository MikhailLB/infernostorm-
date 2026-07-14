import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../bridge/insight.dart';
import '../env/app_config.dart';
import '../net/blaze_storage.dart';
import '../net/signal_service.dart';
import '../net/net_probe.dart';
import 'gate_screen.dart' deferred as gate;

/// Notification permission promo screen.
/// Uses static images instead of video (InfernoStorm-specific).
/// Button design differs from AdventureRoad: fire-orange gradient, sharp corners.
class AlertOptIn extends StatefulWidget {
  final BlazeStorage storage;
  final SignalService signal;
  final NetProbe probe;
  final String targetUrl;

  const AlertOptIn({
    super.key,
    required this.storage,
    required this.signal,
    required this.probe,
    required this.targetUrl,
  });

  @override
  State<AlertOptIn> createState() => _AlertOptInState();
}

class _AlertOptInState extends State<AlertOptIn>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowCtrl;
  late Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    Insight.screen('push_invite');

    // Allow free rotation so notification promo art switches between
    // portrait/landscape. Re-applied post-frame to defeat any late
    // setPreferredOrientations from a previous screen's dispose.
    _unlockRotation();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlockRotation());

    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut),
    );
  }

  void _unlockRotation() {
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    super.dispose();
  }

  Future<void> _onAccept() async {
    Insight.event('push_invite_accept');
    // requestPermission handles all outcomes:
    //   granted → setNotifGranted(true) so shouldShowNotifScreen stays false
    //   OS-deny → setNotifOsDenied so we never re-prompt from our side
    final granted = await widget.signal.requestPermission();
    Insight.tag('notif_permission', granted ? 'granted' : 'denied');
    Insight.event(granted ? 'push_granted' : 'push_denied');
    if (!mounted) return;
    await _proceed();
  }

  Future<void> _onSkip() async {
    Insight.event('push_invite_skip');
    Insight.tag('notif_permission', 'skipped');
    // Skip re-arms the promo for AppConfig.notifRetrySeconds (3 days by default).
    final until = DateTime.now().millisecondsSinceEpoch ~/ 1000 +
        AppConfig.notifRetrySeconds;
    await widget.storage.setNotifSkipUntil(until);
    if (!mounted) return;
    await _proceed();
  }

  Future<void> _proceed() async {
    await gate.loadLibrary();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => gate.GateScreen(
          url: widget.targetUrl,
          storage: widget.storage,
          signal: widget.signal,
          probe: widget.probe,
        ),
      ),
    );
  }

  // Source PNG size — Vertical_/Horizontal_Notifications_Screen.png.
  static const Size _landArt = Size(2400, 1080);
  static const Size _portArt = Size(1080, 2400);

  // Button placement in art-space fractions. Reproduces the same "cover"
  // math as OfflineWall so both notification and no-wifi screens stay
  // consistent across every device.
  // Landscape: Accept + Skip on a single row, both anchored at the
  // Skip line (by=0.96) and mirrored around the horizontal center.
  static const _NotifPlacement _landPlacement = _NotifPlacement(
    acceptCx: 0.395,
    acceptBy: 0.960,
    skipCx: 0.605,
    skipBy: 0.960,
    widthFrac: 0.200,
    heightPx: 48,
    minWidthPx: 160,
    maxWidthPx: 360,
  );
  static const _NotifPlacement _portPlacement = _NotifPlacement(
    acceptCx: 0.500,
    acceptBy: 0.870,
    skipCx: 0.500,
    skipBy: 0.955,
    widthFrac: 0.860,
    heightPx: 60,
    minWidthPx: 240,
    maxWidthPx: 640,
  );

  @override
  Widget build(BuildContext context) {
    return OrientationBuilder(builder: (ctx, orientation) {
      final isLand = orientation == Orientation.landscape;
      final bg = isLand
          ? 'assets/Notifications/Horizontal_Notifications_Screen.png'
          : 'assets/Notifications/Vertical_Notifications_Screen.png';
      final artSize = isLand ? _landArt : _portArt;
      final placement = isLand ? _landPlacement : _portPlacement;

      return Scaffold(
        backgroundColor: Colors.black,
        body: LayoutBuilder(builder: (_, cons) {
          final viewport = Size(cons.maxWidth, cons.maxHeight);
          final accept = placement.resolveAccept(
              viewport: viewport, artSize: artSize);
          final skip = placement.resolveSkip(
              viewport: viewport, artSize: artSize);

          return Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(bg, fit: BoxFit.cover),
              Positioned(
                left: accept.left,
                top: accept.top,
                width: accept.width,
                height: accept.height,
                child: _AcceptBtn(glowAnim: _glowAnim, onTap: _onAccept),
              ),
              Positioned(
                left: skip.left,
                top: skip.top,
                width: skip.width,
                height: skip.height,
                child: _SkipBtn(onTap: _onSkip),
              ),
            ],
          );
        }),
      );
    });
  }
}

/// Placement spec for both notification buttons, resolved against the
/// current viewport with BoxFit.cover math (see OfflineWall for details).
class _NotifPlacement {
  final double acceptCx;
  final double acceptBy;
  final double skipCx;
  final double skipBy;
  final double widthFrac;
  final double heightPx;
  final double minWidthPx;
  final double maxWidthPx;

  const _NotifPlacement({
    required this.acceptCx,
    required this.acceptBy,
    required this.skipCx,
    required this.skipBy,
    required this.widthFrac,
    required this.heightPx,
    required this.minWidthPx,
    required this.maxWidthPx,
  });

  Rect resolveAccept({required Size viewport, required Size artSize}) =>
      _resolve(acceptCx, acceptBy, viewport, artSize);

  Rect resolveSkip({required Size viewport, required Size artSize}) =>
      _resolve(skipCx, skipBy, viewport, artSize);

  Rect _resolve(double cx, double by, Size viewport, Size artSize) {
    final coverScale = math.max(
      viewport.width / artSize.width,
      viewport.height / artSize.height,
    );
    final renderedW = artSize.width * coverScale;
    final renderedH = artSize.height * coverScale;
    final imgLeft = (viewport.width - renderedW) / 2;
    final imgTop = (viewport.height - renderedH) / 2;

    final btnCx = imgLeft + renderedW * cx;
    final btnBy = imgTop + renderedH * by;
    final btnW =
        (renderedW * widthFrac).clamp(minWidthPx, maxWidthPx).toDouble();

    return Rect.fromLTWH(btnCx - btnW / 2, btnBy - heightPx, btnW, heightPx);
  }
}

// ── Accept button ─────────────────────────────────────────────────────────────

class _AcceptBtn extends StatefulWidget {
  final Animation<double> glowAnim;
  final VoidCallback onTap;

  const _AcceptBtn({required this.glowAnim, required this.onTap});

  @override
  State<_AcceptBtn> createState() => _AcceptBtnState();
}

class _AcceptBtnState extends State<_AcceptBtn> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) {
        setState(() => _down = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _down = false),
      child: AnimatedBuilder(
        animation: widget.glowAnim,
        builder: (_, __) => AnimatedScale(
          scale: _down ? 0.95 : 1.0,
          duration: const Duration(milliseconds: 80),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _down
                    ? [const Color(0xFFE0A800), const Color(0xFFCC8A00)]
                    : [const Color(0xFFFFD54F), const Color(0xFFFFB300)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFFB300)
                      .withValues(alpha: _down ? 0.25 : widget.glowAnim.value),
                  blurRadius: _down ? 6 : 16 + widget.glowAnim.value * 14,
                  spreadRadius: _down ? 0 : widget.glowAnim.value * 3,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            // FittedBox lets the icon+text pair auto-shrink to fit the
            // parent Positioned box; keeps the visual balance identical
            // across small phones and tablets.
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.local_fire_department,
                      color: Color(0xFF3A2400),
                      size: 22,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Accept',
                      style: TextStyle(
                        color: Color(0xFF3A2400),
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Skip button ───────────────────────────────────────────────────────────────

class _SkipBtn extends StatefulWidget {
  final VoidCallback onTap;

  const _SkipBtn({required this.onTap});

  @override
  State<_SkipBtn> createState() => _SkipBtnState();
}

class _SkipBtnState extends State<_SkipBtn> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) {
        setState(() => _down = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 80),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _down
                  ? [const Color(0xFFE0A800), const Color(0xFFCC8A00)]
                  : [const Color(0xFFFFD54F), const Color(0xFFFFB300)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFB300)
                    .withValues(alpha: _down ? 0.2 : 0.4),
                blurRadius: _down ? 6 : 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'Skip',
                style: TextStyle(
                  color: Color(0xFF3A2400),
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
