import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../bridge/insight.dart';

const List<String> _cardImages = [
  'assets/crystal4.webp',
  'assets/devil 5.webp',
  'assets/dragon3.webp',
  'assets/fenix1.webp',
  'assets/giantfire8.webp',
  'assets/golem2.webp',
  'assets/hellgate9.webp',
  'assets/light6.webp',
  'assets/waterfall7.webp',
];

class CardModel {
  final int id;
  final String imagePath;
  bool isFaceUp;
  bool isMatched;

  CardModel({
    required this.id,
    required this.imagePath,
    this.isFaceUp = false,
    this.isMatched = false,
  });
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  late List<CardModel> _cards;

  int? _firstFlipped;
  int? _secondFlipped;
  bool _isChecking = false;

  int _moves = 0;
  int _matchedPairs = 0;
  bool _gameOver = false;

  late AnimationController _volcanoIdle;
  late Animation<double> _volcanoFloat;
  late AnimationController _volcanoReaction;
  late Animation<double> _volcanoScale;

  final List<AnimationController> _cardControllers = [];
  final List<Animation<double>> _cardFlipAnims = [];

  @override
  void initState() {
    super.initState();
    Insight.screen('game');
    Insight.event('game_start');
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initCards();
    _initVolcanoAnims();
  }

  // ─── Cards ────────────────────────────────────────────────────────────────

  void _initCards() {
    final images = [..._cardImages, ..._cardImages]..shuffle(Random());
    _cards = List.generate(18, (i) => CardModel(id: i, imagePath: images[i]));

    for (int i = 0; i < 18; i++) {
      final ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 380),
      );
      _cardControllers.add(ctrl);
      _cardFlipAnims.add(
        Tween<double>(begin: 0, end: 1)
            .animate(CurvedAnimation(parent: ctrl, curve: Curves.easeInOut)),
      );
    }
  }

  void _onCardTap(int index) {
    if (_isChecking) return;
    if (_cards[index].isFaceUp || _cards[index].isMatched) return;

    if (_firstFlipped == null) {
      setState(() {
        _cards[index].isFaceUp = true;
        _firstFlipped = index;
      });
      _cardControllers[index].forward();
    } else if (_secondFlipped == null && index != _firstFlipped) {
      setState(() {
        _cards[index].isFaceUp = true;
        _secondFlipped = index;
        _moves++;
      });
      _cardControllers[index].forward();
      _checkMatch();
    }
  }

  void _checkMatch() {
    final i1 = _firstFlipped!;
    final i2 = _secondFlipped!;
    _isChecking = true;

    Future.delayed(const Duration(milliseconds: 750), () {
      if (!mounted) return;

      if (_cards[i1].imagePath == _cards[i2].imagePath) {
        setState(() {
          _cards[i1].isMatched = true;
          _cards[i2].isMatched = true;
          _matchedPairs++;
          _firstFlipped = null;
          _secondFlipped = null;
          _isChecking = false;
        });
        _volcanoReaction.forward(from: 0);

        if (_matchedPairs == 9) {
          Insight.event('game_win');
          Insight.tag('game_moves', _moves.toString());
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) setState(() => _gameOver = true);
          });
        }
      } else {
        setState(() {
          _cards[i1].isFaceUp = false;
          _cards[i2].isFaceUp = false;
        });
        _cardControllers[i1].reverse();
        _cardControllers[i2].reverse();

        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted) {
            setState(() {
              _firstFlipped = null;
              _secondFlipped = null;
              _isChecking = false;
            });
          }
        });
      }
    });
  }

  // ─── Volcano ──────────────────────────────────────────────────────────────

  void _initVolcanoAnims() {
    _volcanoIdle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _volcanoFloat = Tween<double>(begin: -5, end: 5).animate(
      CurvedAnimation(parent: _volcanoIdle, curve: Curves.easeInOut),
    );

    _volcanoReaction = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _volcanoScale = Tween<double>(begin: 1.0, end: 1.22).animate(
      CurvedAnimation(parent: _volcanoReaction, curve: Curves.bounceOut),
    );
    _volcanoReaction.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _volcanoReaction.reverse();
      }
    });
  }

  // ─── Restart ──────────────────────────────────────────────────────────────

  void _restartGame() {
    for (final c in _cardControllers) {
      c.dispose();
    }
    _cardControllers.clear();
    _cardFlipAnims.clear();

    setState(() {
      _firstFlipped = null;
      _secondFlipped = null;
      _isChecking = false;
      _moves = 0;
      _matchedPairs = 0;
      _gameOver = false;
      _initCards();
    });
  }

  @override
  void dispose() {
    _volcanoIdle.dispose();
    _volcanoReaction.dispose();
    for (final c in _cardControllers) {
      c.dispose();
    }
    super.dispose();
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Фон — обновлённый вертикальный экран загрузки
          Image.asset('assets/Vertical_LoadingScreen.webp', fit: BoxFit.cover),
          Container(color: Colors.black.withValues(alpha: 0.55)),
          SafeArea(child: _buildGameLayout()),
          if (_gameOver) _buildWinOverlay(),
        ],
      ),
    );
  }

  Widget _buildGameLayout() {
    return LayoutBuilder(builder: (context, constraints) {
      const topBarH = 52.0;
      const hPad = 6.0;
      const vPad = 4.0;
      const cols = 3;
      const rows = 6;
      const spacing = 5.0;
      // Фиксированная высота зоны вулкана — он располагается ПОД сеткой
      const volcanoZoneH = 82.0;

      final availW = constraints.maxWidth - hPad * 2;
      // Высота сетки = всё пространство минус топбар, отступы и зона вулкана
      final gridH = constraints.maxHeight - topBarH - vPad * 3 - volcanoZoneH;

      final cardW = (availW - spacing * (cols - 1)) / cols;
      final cardH = (gridH - spacing * (rows - 1)) / rows;

      return Column(
        children: [
          SizedBox(height: topBarH, child: _buildTopBar()),
          const SizedBox(height: vPad),
          // Сетка с явной высотой — не вылезает за экран
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: hPad),
            child: SizedBox(
              height: gridH,
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisSpacing: spacing,
                  crossAxisSpacing: spacing,
                  childAspectRatio: cardW / cardH,
                ),
                itemCount: 18,
                itemBuilder: (_, i) => _buildCard(i),
              ),
            ),
          ),
          const SizedBox(height: vPad),
          // Зона вулкана — под сеткой, смещён влево от центра
          SizedBox(
            height: volcanoZoneH,
            child: Align(
              alignment: Alignment.center,
              child: _buildVolcano(volcanoZoneH - 4),
            ),
          ),
          const SizedBox(height: vPad),
        ],
      );
    });
  }

  // ─── Top bar ──────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          _BackBtn(onTap: () => Navigator.of(context).pop()),
          const Spacer(),
          _StatChip(icon: Icons.touch_app, value: 'Moves: $_moves'),
          const SizedBox(width: 8),
          _StatChip(icon: Icons.favorite, value: '$_matchedPairs/9'),
        ],
      ),
    );
  }

  // ─── Card ─────────────────────────────────────────────────────────────────

  Widget _buildCard(int index) {
    final card = _cards[index];

    return GestureDetector(
      onTap: () => _onCardTap(index),
      child: AnimatedBuilder(
        animation: _cardFlipAnims[index],
        builder: (_, __) {
          final v = _cardFlipAnims[index].value;
          final showFront = v >= 0.5;
          final angle = showFront ? (v - 1) * pi : v * pi;

          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateY(angle),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(7),
                boxShadow: [
                  BoxShadow(
                    color: card.isMatched
                        ? Colors.orange.withValues(alpha: 0.65)
                        : Colors.black.withValues(alpha: 0.45),
                    blurRadius: card.isMatched ? 10 : 3,
                    spreadRadius: card.isMatched ? 1 : 0,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: showFront ? _cardFront(card) : _cardBack(),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _cardFront(CardModel card) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(card.imagePath, fit: BoxFit.cover),
        if (card.isMatched)
          Container(
            color: Colors.orange.withValues(alpha: 0.22),
            child: const Center(
              child: Icon(Icons.check_circle,
                  color: Colors.orangeAccent, size: 26),
            ),
          ),
      ],
    );
  }

  Widget _cardBack() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.orange.shade900,
            Colors.deepOrange.shade800,
            Colors.red.shade900,
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Icon(
              Icons.local_fire_department,
              color: Colors.orange.withValues(alpha: 0.55),
              size: 28,
            ),
          ),
          Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: Colors.orange.shade700.withValues(alpha: 0.45),
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(7),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Volcano overlay ──────────────────────────────────────────────────────

  Widget _buildVolcano(double height) {
    return AnimatedBuilder(
      animation: Listenable.merge([_volcanoIdle, _volcanoReaction]),
      builder: (_, child) => Transform.translate(
        offset: Offset(0, _volcanoFloat.value),
        child: Transform.scale(scale: _volcanoScale.value, child: child),
      ),
      child: Image.asset(
        'assets/volcano1.webp',
        height: height,
        fit: BoxFit.contain,
      ),
    );
  }

  // ─── Win overlay ──────────────────────────────────────────────────────────

  Widget _buildWinOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.78),
      child: Center(
        child: Container(
          width: 280,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.orange.shade900, Colors.deepOrange.shade900],
            ),
            border: Border.all(color: Colors.orange.shade400, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.orange.withValues(alpha: 0.5),
                blurRadius: 32,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/volcano1.webp', height: 80),
              const SizedBox(height: 12),
              Text(
                'YOU WIN!',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange.shade200,
                  letterSpacing: 3,
                  shadows: const [
                    Shadow(
                        color: Colors.black,
                        offset: Offset(2, 2),
                        blurRadius: 6),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Moves: $_moves',
                style: TextStyle(
                  fontSize: 17,
                  color: Colors.orange.shade300,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 22),
              // Кнопки в колонке — нет overflow, нет "странного текста"
              _WinButton(
                label: 'Play Again',
                icon: Icons.refresh,
                onTap: _restartGame,
              ),
              const SizedBox(height: 10),
              _WinButton(
                label: 'Menu',
                icon: Icons.home,
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

class _BackBtn extends StatelessWidget {
  final VoidCallback onTap;
  const _BackBtn({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.orange.shade700, width: 1),
        ),
        child: const Icon(Icons.arrow_back_ios_new,
            color: Colors.orange, size: 18),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String value;
  const _StatChip({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.shade700, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.orange, size: 14),
          const SizedBox(width: 5),
          Text(
            value,
            style: const TextStyle(
              color: Colors.orange,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _WinButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _WinButton(
      {required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.shade400, width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.orange.shade200, size: 20),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: Colors.orange.shade200,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
