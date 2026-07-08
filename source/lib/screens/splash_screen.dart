import 'package:flutter/material.dart';
import '../utils/page_transitions.dart';
import '../utils/theme.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _textController;
  late final Animation<double> _fadeIn;
  late final Animation<double> _scaleIn;

  late final AnimationController _flyController;

  static const int _waitSeconds = 5;

  @override
  void initState() {
    super.initState();
    _textController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _fadeIn = CurvedAnimation(parent: _textController, curve: Curves.easeOut);
    _scaleIn = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeOutBack),
    );
    _textController.forward();

    // Aircraft icon grows and flies left-to-right across the 5 second wait.
    _flyController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: _waitSeconds),
    );
    _flyController.forward();

    Future.delayed(const Duration(seconds: _waitSeconds), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(fadeSlideRoute(const HomeScreen()));
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _flyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeIn,
          child: ScaleTransition(
            scale: _scaleIn,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Image.asset('assets/branding/splash_uuds_logo.png', height: 130, fit: BoxFit.contain),
                  const SizedBox(height: 20),
                  const Text(
                    'UUDS',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: kPrimary, fontSize: 48, fontWeight: FontWeight.w900, letterSpacing: 1),
                  ),
                  const Text(
                    'Aircraft Parts',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: kPrimary, fontSize: 26, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Receiving & Despatching\nRecords',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF3A3A3A), fontSize: 19, fontWeight: FontWeight.w600, height: 1.3),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Center(
                      child: SizedBox(
                        width: 260,
                        height: 160,
                        child: Image.asset(
                          'assets/branding/splash_jet.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Loading indicator: a small aircraft icon that grows and
                  // flies from left to right as the wait progresses, with a faint smoke trail.
                  SizedBox(
                    height: 34,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return AnimatedBuilder(
                          animation: _flyController,
                          builder: (context, child) {
                            final t = Curves.easeInOut.transform(_flyController.value.clamp(0.0, 1.0));
                            const minSize = 14.0;
                            const maxSize = 30.0;
                            final size = minSize + (maxSize - minSize) * t;
                            final maxX = constraints.maxWidth - size;
                            final aircraftLeft = maxX * t;
                            return Stack(
                              children: [
                                // Smoke trail dots behind the aircraft
                                for (int i = 1; i <= 3; i++) ...[
                                  Positioned(
                                    left: aircraftLeft - (size * 0.35 * i) - (8 * t),
                                    top: (34 - size * 0.3) / 2 + (size * 0.15),
                                    child: Opacity(
                                      opacity: 0.4 - (i * 0.1),
                                      child: Container(
                                        width: size * (0.45 - i * 0.1),
                                        height: size * (0.45 - i * 0.1),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.withOpacity(0.5 - i * 0.12),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                                Positioned(
                                  left: aircraftLeft,
                                  top: (34 - size) / 2,
                                  child: Transform.rotate(
                                    angle: -0.6, // slight nose-up, pointing rightward
                                    child: Icon(Icons.flight, size: size, color: kPrimary),
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Divider(height: 1, color: Color(0xFFD8D8D8)),
                  const SizedBox(height: 10),
                  const Text(
                    'Designed & Developed by Khurram Munir Basra',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF555555), fontSize: 12.5),
                  ),
                  const SizedBox(height: 10),
                  Image.asset('assets/branding/splash_kmb_logo.png', height: 46, fit: BoxFit.contain),
                  const SizedBox(height: 6),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

