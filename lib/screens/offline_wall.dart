import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// No-internet screen. Title and subtitle are baked into the background
/// art — we overlay only the Retry pill.
///
/// The button is positioned in art-pixel coordinates (relative to the
/// source PNG's 2400×1080 / 1080×2400 canvas). We reproduce Flutter's
/// BoxFit.cover math to find where the art is actually rendered inside
/// the viewport and then place the button in that image-local frame.
/// This keeps the button sitting on the same spot of the art on every
/// device — phones, foldables, tablets — regardless of aspect ratio.
class OfflineWall extends StatefulWidget {
  final WidgetBuilder onRetry;

  const OfflineWall({super.key, required this.onRetry});

  @override
  State<OfflineWall> createState() => _OfflineWallState();
}

class _OfflineWallState extends State<OfflineWall>
    with SingleTickerProviderStateMixin {
  bool _busy = false;
  late AnimationController _btnPress;
  late Animation<double> _btnScale;

  // Source PNG size (identical for the notification art too).
  static const Size _landArt = Size(2400, 1080);
  static const Size _portArt = Size(1080, 2400);

  // Retry pill in art-space, measured from the source PNG:
  //   cx / by   — center-x / bottom-y as fractions of the art.
  //   widthFrac — pill width as a fraction of the art width.
  //   heightPx  — visual height in logical pixels (constant across devices).
  static const _RetryPlacement _landPlacement = _RetryPlacement(
    cx: 0.500,
    by: 0.920,
    widthFrac: 0.290,
    heightPx: 54,
    minWidthPx: 200,
    maxWidthPx: 520,
  );
  static const _RetryPlacement _portPlacement = _RetryPlacement(
    cx: 0.500,
    by: 0.870,
    widthFrac: 0.820,
    heightPx: 54,
    minWidthPx: 240,
    maxWidthPx: 640,
  );

  @override
  void initState() {
    super.initState();

    _unlockRotation();
    _applyEdgeToEdge();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _unlockRotation();
      _applyEdgeToEdge();
    });

    _btnPress = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _btnScale = Tween<double>(begin: 1.0, end: 0.93).animate(
      CurvedAnimation(parent: _btnPress, curve: Curves.easeOut),
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

  /// Full-bleed background: hide status/navigation bars so the art
  /// (and the Retry pill placed relative to it) is not offset by any
  /// system safe-zone insets.
  void _applyEdgeToEdge() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _btnPress.dispose();
    // Restore normal system UI for the next screen.
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  Future<void> _retry() async {
    if (_busy) return;
    await _btnPress.forward();
    await _btnPress.reverse();
    setState(() => _busy = true);
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: widget.onRetry),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OrientationBuilder(builder: (ctx, orientation) {
      final isLand = orientation == Orientation.landscape;
      final bg = isLand
          ? 'assets/Nowifi/Horizontal_Nowifi_Screen.png'
          : 'assets/Nowifi/Vertical_Nowifi_Screen.png';
      final artSize = isLand ? _landArt : _portArt;
      final placement = isLand ? _landPlacement : _portPlacement;

      return Scaffold(
        backgroundColor: Colors.black,
        body: LayoutBuilder(builder: (_, cons) {
          final rect = placement.resolve(
            viewport: Size(cons.maxWidth, cons.maxHeight),
            artSize: artSize,
          );

          return Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(bg, fit: BoxFit.cover),
              Positioned(
                left: rect.left,
                top: rect.top,
                width: rect.width,
                height: rect.height,
                child: ScaleTransition(
                  scale: _btnScale,
                  child: _RetryPill(busy: _busy, onTap: _busy ? null : _retry),
                ),
              ),
            ],
          );
        }),
      );
    });
  }
}

/// Immutable placement spec resolved against the viewport at build-time.
class _RetryPlacement {
  final double cx;
  final double by;
  final double widthFrac;
  final double heightPx;
  final double minWidthPx;
  final double maxWidthPx;

  const _RetryPlacement({
    required this.cx,
    required this.by,
    required this.widthFrac,
    required this.heightPx,
    required this.minWidthPx,
    required this.maxWidthPx,
  });

  /// Computes the pill's screen-space Rect given the current viewport size.
  /// Mirrors BoxFit.cover:  scale = max(W/artW, H/artH).
  Rect resolve({required Size viewport, required Size artSize}) {
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
    final btnH = heightPx;

    return Rect.fromLTWH(btnCx - btnW / 2, btnBy - btnH, btnW, btnH);
  }
}

class _RetryPill extends StatelessWidget {
  final bool busy;
  final VoidCallback? onTap;

  const _RetryPill({required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: busy
            ? null
            : const LinearGradient(
                colors: [Color(0xFFFFD54F), Color(0xFFFFB300)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        color: busy ? const Color(0xFFFFB300).withValues(alpha: 0.3) : null,
        borderRadius: BorderRadius.circular(16),
        boxShadow: busy
            ? []
            : [
                BoxShadow(
                  color: const Color(0xFFFFB300).withValues(alpha: 0.55),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Center(
            child: busy
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor:
                              AlwaysStoppedAnimation(Color(0xFF3A2400)),
                        ),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Connecting...',
                        style: TextStyle(
                          color: Color(0xFF3A2400),
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  )
                : const Text(
                    'Retry',
                    style: TextStyle(
                      color: Color(0xFF3A2400),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.7,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
