import 'package:flutter/material.dart';

/// No-internet screen with InfernoStorm background image.
/// Different from AdventureRoad: uses image bg, not dark solid color;
/// Retry button uses fire-orange gradient instead of gold.
class OfflineWall extends StatefulWidget {
  final WidgetBuilder onRetry;

  const OfflineWall({super.key, required this.onRetry});

  @override
  State<OfflineWall> createState() => _OfflineWallState();
}

class _OfflineWallState extends State<OfflineWall>
    with TickerProviderStateMixin {
  bool _busy = false;
  late AnimationController _iconPulse;
  late Animation<double> _iconScale;
  late AnimationController _btnPress;
  late Animation<double> _btnScale;

  @override
  void initState() {
    super.initState();

    _iconPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _iconScale = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _iconPulse, curve: Curves.easeInOut),
    );

    _btnPress = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _btnScale = Tween<double>(begin: 1.0, end: 0.93).animate(
      CurvedAnimation(parent: _btnPress, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _iconPulse.dispose();
    _btnPress.dispose();
    super.dispose();
  }

  Future<void> _retry() async {
    if (_busy) return;
    await _btnPress.forward();
    await _btnPress.reverse();
    setState(() => _busy = true);
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
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

      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(bg, fit: BoxFit.cover),
            Container(color: Colors.black.withValues(alpha: 0.52)),
            SafeArea(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isLand ? size.width * 0.25 : 36,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Pulsing wifi-off icon
                    AnimatedBuilder(
                      animation: _iconScale,
                      builder: (_, child) =>
                          Transform.scale(scale: _iconScale.value, child: child),
                      child: Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.deepOrange.withValues(alpha: 0.18),
                          border: Border.all(
                            color: Colors.deepOrange.withValues(alpha: 0.5),
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.wifi_off_rounded,
                          size: 46,
                          color: Colors.deepOrange,
                        ),
                      ),
                    ),

                    const SizedBox(height: 28),

                    const Text(
                      'No Internet Connection',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 10),

                    Text(
                      'Check your connection and tap Retry',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 44),

                    ScaleTransition(
                      scale: _btnScale,
                      child: SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: _busy
                                ? null
                                : const LinearGradient(
                                    colors: [Color(0xFFE64500), Color(0xFFFF6B00)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                            color: _busy
                                ? Colors.deepOrange.withValues(alpha: 0.3)
                                : null,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: _busy
                                ? []
                                : [
                                    BoxShadow(
                                      color: Colors.deepOrange.withValues(alpha: 0.45),
                                      blurRadius: 14,
                                      offset: const Offset(0, 5),
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
                                        children: [
                                          const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.5,
                                              valueColor:
                                                  AlwaysStoppedAnimation(Colors.deepOrange),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            'Connecting...',
                                            style: TextStyle(
                                              color: Colors.deepOrange
                                                  .withValues(alpha: 0.9),
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      )
                                    : const Text(
                                        'Retry',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 17,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.5,
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
              ),
            ),
          ],
        ),
      );
    });
  }
}
