import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// No-internet screen. Text "NO INTERNET CONNECTION / Check your connection
/// and try again" is baked into the background art — we only draw Retry.
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

  @override
  void initState() {
    super.initState();

    // Allow free rotation on this screen — switches between portrait/landscape art.
    // Re-applied post-frame in case the previous screen's dispose() runs late
    // and tries to lock back to portrait.
    _unlockRotation();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlockRotation());

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

  @override
  void dispose() {
    _btnPress.dispose();
    super.dispose();
  }

  Future<void> _retry() async {
    if (_busy) return;
    await _btnPress.forward();
    await _btnPress.reverse();
    setState(() => _busy = true);
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    // Restore portrait lock — next screen (BootScreen) re-allows rotation if needed
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
      final size = MediaQuery.of(ctx).size;

      // Portrait: full-width with small side pad.
      // Landscape: left pad aligns with the slate; right pad is 15px shorter
      // so the button extends 15px further to the right (asymmetric on purpose).
      final btnLeftPad = isLand ? size.width * 0.34 : 36.0;
      final btnRightPad = isLand ? size.width * 0.34 - 15 : 36.0;
      final btnBottomOffset = isLand ? size.height * 0.08 : size.height * 0.12;

      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(bg, fit: BoxFit.cover),

            // Only the Retry button — title/subtitle are part of the art
            Positioned(
              left: btnLeftPad,
              right: btnRightPad,
              bottom: btnBottomOffset,
              child: SafeArea(
                top: false,
                child: ScaleTransition(
                  scale: _btnScale,
                  child: SizedBox(
                    height: 54,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: _busy
                            ? null
                            : const LinearGradient(
                                colors: [Color(0xFFFFD54F), Color(0xFFFFB300)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                        color: _busy
                            ? const Color(0xFFFFB300).withValues(alpha: 0.3)
                            : null,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: _busy
                            ? []
                            : [
                                BoxShadow(
                                  color: const Color(0xFFFFB300)
                                      .withValues(alpha: 0.55),
                                  blurRadius: 18,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: _busy ? null : _retry,
                          child: Center(
                            child: _busy
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: const [
                                      SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          valueColor: AlwaysStoppedAnimation(
                                              Color(0xFF3A2400)),
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
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}
