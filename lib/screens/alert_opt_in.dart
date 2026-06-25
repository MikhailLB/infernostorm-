import 'package:flutter/material.dart';
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
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    super.dispose();
  }

  Future<void> _onAccept() async {
    final granted = await widget.signal.requestPermission();
    if (!mounted) return;
    if (!granted) await _scheduleRetry();
    await _proceed();
  }

  Future<void> _onSkip() async {
    await _scheduleRetry();
    if (!mounted) return;
    await _proceed();
  }

  Future<void> _scheduleRetry() async {
    final until = DateTime.now().millisecondsSinceEpoch ~/ 1000 +
        AppConfig.notifRetrySeconds;
    await widget.storage.setNotifSkipUntil(until);
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

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return OrientationBuilder(builder: (ctx, orientation) {
      final isLand = orientation == Orientation.landscape;
      final bg = isLand
          ? 'assets/Notifications/Horizontal_Notifications_Screen.png'
          : 'assets/Notifications/Vertical_Notifications_Screen.png';

      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(bg, fit: BoxFit.cover),

            // Buttons overlay
            if (!isLand)
              Positioned(
                left: size.width * 0.08,
                right: size.width * 0.08,
                bottom: size.height * 0.07,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _AcceptBtn(glowAnim: _glowAnim, onTap: _onAccept),
                    const SizedBox(height: 18),
                    _SkipBtn(onTap: _onSkip),
                  ],
                ),
              )
            else
              Positioned(
                left: 0,
                right: 0,
                bottom: size.height * 0.07,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: size.width * 0.35,
                      child: _AcceptBtn(
                          glowAnim: _glowAnim,
                          onTap: _onAccept,
                          compact: true),
                    ),
                    const SizedBox(height: 10),
                    _SkipBtn(onTap: _onSkip, compact: true),
                  ],
                ),
              ),
          ],
        ),
      );
    });
  }
}

// ── Accept button ─────────────────────────────────────────────────────────────

class _AcceptBtn extends StatefulWidget {
  final Animation<double> glowAnim;
  final VoidCallback onTap;
  final bool compact;

  const _AcceptBtn({
    required this.glowAnim,
    required this.onTap,
    this.compact = false,
  });

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
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              vertical: widget.compact ? 13 : 19,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _down
                    ? [const Color(0xFFCC3300), const Color(0xFFDD5500)]
                    : [const Color(0xFFFF4500), const Color(0xFFFF7000)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.deepOrange
                      .withValues(alpha: _down ? 0.2 : widget.glowAnim.value),
                  blurRadius: _down ? 6 : 16 + widget.glowAnim.value * 14,
                  spreadRadius: _down ? 0 : widget.glowAnim.value * 3,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.local_fire_department,
                  color: Colors.white,
                  size: widget.compact ? 18 : 22,
                ),
                const SizedBox(width: 8),
                Text(
                  'Accept',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: widget.compact ? 15 : 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
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
  final bool compact;

  const _SkipBtn({required this.onTap, this.compact = false});

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
      child: AnimatedOpacity(
        opacity: _down ? 0.45 : 0.85,
        duration: const Duration(milliseconds: 80),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: widget.compact ? 5 : 9),
          child: Center(
            child: Text(
              'Skip',
              style: TextStyle(
                color: Colors.white,
                fontSize: widget.compact ? 15 : 20,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
                shadows: const [
                  Shadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 2)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
