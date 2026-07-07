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

  late final AnimationController _dotsController;
  int _activeDot = 0;

  static const int _totalDots = 5;
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

    // 5 dots lighting up one by one across the 5 second wait.
    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: _waitSeconds),
    )..addListener(() {
        final newDot = (_dotsController.value * _totalDots).floor().clamp(0, _totalDots - 1);
        if (newDot != _activeDot) {
          setState(() => _activeDot = newDot);
        }
      });
    _dotsController.forward();

    Future.delayed(const Duration(seconds: _waitSeconds), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(fadeSlideRoute(const HomeScreen()));
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _dotsController.dispose();
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
                  // 5-dot loading indicator - lights up progressively during the wait.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_totalDots, (i) {
                      final lit = i <= _activeDot;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: lit ? 12 : 8,
                        height: lit ? 12 : 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: lit ? kPrimary : kPrimary.withOpacity(0.25),
                        ),
                      );
                    }),
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

