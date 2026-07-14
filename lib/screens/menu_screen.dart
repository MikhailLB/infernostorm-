import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../bridge/insight.dart';
import 'game_screen.dart';
import 'info_panel.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _volcanoController;
  late Animation<double> _volcanoFloat;

  @override
  void initState() {
    super.initState();
    Insight.screen('menu');
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _volcanoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    _volcanoFloat = Tween<double>(begin: -6, end: 6).animate(
      CurvedAnimation(parent: _volcanoController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _volcanoController.dispose();
    super.dispose();
  }

  void _openGame() {
    Insight.event('menu_open_game');
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const GameScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  void _openWebView(String title, String url) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => InfoPanel(title: title, url: url)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Фон — обновлённый вертикальный экран загрузки
          Image.asset('assets/Vertical_LoadingScreen.webp', fit: BoxFit.cover),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.25),
                  Colors.black.withValues(alpha: 0.65),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 32),
                const Spacer(),
                AnimatedBuilder(
                  animation: _volcanoFloat,
                  builder: (_, child) => Transform.translate(
                    offset: Offset(0, _volcanoFloat.value),
                    child: child,
                  ),
                  child: Image.asset(
                    'assets/volcano1.webp',
                    height: size.height * 0.26,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 28),
                _MenuButton(
                  label: 'PLAY',
                  icon: Icons.local_fire_department,
                  onTap: _openGame,
                  primary: true,
                ),
                const SizedBox(height: 14),
                _MenuButton(
                  label: 'Privacy Policy',
                  icon: Icons.shield_outlined,
                  onTap: () => _openWebView(
                    'Privacy Policy',
                    'https://infernostorm.com/privacy-policy.html',
                  ),
                ),
                const SizedBox(height: 14),
                _MenuButton(
                  label: 'Support',
                  icon: Icons.support_agent,
                  onTap: () => _openWebView(
                    'Support',
                    'https://infernostorm.com/support.html',
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;

  const _MenuButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: w * 0.72,
        padding: EdgeInsets.symmetric(
          vertical: primary ? 16 : 13,
          horizontal: 20,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            colors: primary
                ? [Colors.deepOrange.shade700, Colors.orange.shade500]
                : [
                    Colors.black.withValues(alpha: 0.65),
                    Colors.orange.shade900.withValues(alpha: 0.65),
                  ],
          ),
          border: Border.all(
            color: primary
                ? Colors.orange.shade300
                : Colors.orange.shade700.withValues(alpha: 0.7),
            width: primary ? 2 : 1,
          ),
          boxShadow: [
            if (primary)
              BoxShadow(
                color: Colors.deepOrange.withValues(alpha: 0.5),
                blurRadius: 14,
                spreadRadius: 2,
              ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                color: Colors.orange.shade200, size: primary ? 26 : 20),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: Colors.orange.shade100,
                fontSize: primary ? 22 : 15,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
