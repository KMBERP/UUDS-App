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
                        child: CustomPaint(painter: _JetOutlinePainter()),
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

/// A clean, native line-art widebody jet illustration (drawn with strokes,
/// not a pasted photo/raster) so it reads as a proper part of the screen -
/// three-quarter cruise view with a fuselage, swept wings, tail, and window
/// line detailing, in the app's own navy tone.
class _JetOutlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final stroke = Paint()
      ..color = kPrimary.withOpacity(0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillLight = Paint()
      ..color = kPrimary.withOpacity(0.06)
      ..style = PaintingStyle.fill;

    // Fuselage (nose at left, tail at right)
    final fuselage = Path()
      ..moveTo(w * 0.04, h * 0.56)
      ..quadraticBezierTo(w * 0.06, h * 0.42, w * 0.18, h * 0.40)
      ..lineTo(w * 0.80, h * 0.42)
      ..quadraticBezierTo(w * 0.94, h * 0.44, w * 0.96, h * 0.52)
      ..quadraticBezierTo(w * 0.94, h * 0.58, w * 0.80, h * 0.60)
      ..lineTo(w * 0.18, h * 0.60)
      ..quadraticBezierTo(w * 0.06, h * 0.62, w * 0.04, h * 0.56)
      ..close();
    canvas.drawPath(fuselage, fillLight);
    canvas.drawPath(fuselage, stroke);

    // Cockpit windshield line
    final cockpit = Path()
      ..moveTo(w * 0.07, h * 0.50)
      ..quadraticBezierTo(w * 0.10, h * 0.44, w * 0.16, h * 0.42);
    canvas.drawPath(cockpit, stroke);

    // Passenger window row (small evenly spaced ticks)
    final windowPaint = Paint()
      ..color = kPrimary.withOpacity(0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    for (double x = 0.24; x <= 0.76; x += 0.055) {
      canvas.drawLine(Offset(w * x, h * 0.48), Offset(w * x, h * 0.52), windowPaint);
    }

    // Main swept wing
    final wing = Path()
      ..moveTo(w * 0.38, h * 0.58)
      ..lineTo(w * 0.20, h * 0.92)
      ..lineTo(w * 0.34, h * 0.90)
      ..lineTo(w * 0.54, h * 0.60)
      ..close();
    canvas.drawPath(wing, fillLight);
    canvas.drawPath(wing, stroke);

    // Small winglet at wingtip
    canvas.drawLine(Offset(w * 0.205, h * 0.915), Offset(w * 0.17, h * 0.99), stroke);

    // Tail fin
    final tail = Path()
      ..moveTo(w * 0.82, h * 0.43)
      ..lineTo(w * 0.94, h * 0.10)
      ..lineTo(w * 0.985, h * 0.13)
      ..lineTo(w * 0.90, h * 0.45)
      ..close();
    canvas.drawPath(tail, fillLight);
    canvas.drawPath(tail, stroke);

    // Rear horizontal stabilizer
    final stab = Path()
      ..moveTo(w * 0.86, h * 0.50)
      ..lineTo(w * 0.97, h * 0.44)
      ..lineTo(w * 0.965, h * 0.48)
      ..lineTo(w * 0.87, h * 0.54)
      ..close();
    canvas.drawPath(stab, fillLight);
    canvas.drawPath(stab, stroke);

    // Engine pod under the wing
    final enginePaint = Paint()
      ..color = kPrimary.withOpacity(0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    final engineRect = Rect.fromCenter(center: Offset(w * 0.36, h * 0.74), width: w * 0.10, height: h * 0.14);
    canvas.drawRRect(RRect.fromRectAndRadius(engineRect, Radius.circular(h * 0.05)), enginePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
