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

  late final AnimationController _planeController;
  late final Animation<double> _planeProgress;

  @override
  void initState() {
    super.initState();
    _textController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _fadeIn = CurvedAnimation(parent: _textController, curve: Curves.easeOut);
    _scaleIn = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeOutBack),
    );
    _textController.forward();

    _planeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 3000));
    _planeProgress = CurvedAnimation(parent: _planeController, curve: Curves.easeInOut);
    _planeController.forward();

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(fadeSlideRoute(const HomeScreen()));
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _planeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: kPrimary,
      body: Stack(
        children: [
          // Takeoff animation: plane rises and moves left -> right during the 3s wait.
          AnimatedBuilder(
            animation: _planeProgress,
            builder: (context, child) {
              final t = _planeProgress.value;
              final dx = -0.25 + t * 1.5; // fraction of width, off-left to off-right
              final dy = 0.30 - (t * 0.55); // rises as it moves across (takeoff arc)
              final nose = -0.45 + (t * 0.30); // slight nose-up rotation while climbing
              return Positioned(
                left: size.width * dx,
                top: size.height * dy,
                child: Transform.rotate(
                  angle: nose,
                  child: const _JetSilhouette(size: 78),
                ),
              );
            },
          ),
          Center(
            child: FadeTransition(
              opacity: _fadeIn,
              child: ScaleTransition(
                scale: _scaleIn,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 36),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Image.asset('assets/branding/logo.png', fit: BoxFit.contain),
                      ),
                      const SizedBox(height: 26),
                      const Text(
                        'UUDS Aircraft Parts\nReceiving and Dispatching Records',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          height: 1.3,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 18,
            child: FadeTransition(
              opacity: _fadeIn,
              child: const Text(
                'Designed & Developed By Khurram Munir Basra',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 11.5, letterSpacing: 0.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A simple, generic widebody-jet silhouette drawn in code (no branded livery/logo).
class _JetSilhouette extends StatelessWidget {
  final double size;
  const _JetSilhouette({required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * 0.55,
      child: CustomPaint(painter: _JetPainter()),
    );
  }
}

class _JetPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final fill = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // Fuselage
    final fuselage = Path()
      ..moveTo(w * 0.02, h * 0.55)
      ..quadraticBezierTo(w * 0.05, h * 0.40, w * 0.20, h * 0.42)
      ..lineTo(w * 0.82, h * 0.46)
      ..quadraticBezierTo(w * 1.00, h * 0.48, w * 0.97, h * 0.56)
      ..quadraticBezierTo(w * 0.80, h * 0.60, w * 0.20, h * 0.60)
      ..quadraticBezierTo(w * 0.05, h * 0.62, w * 0.02, h * 0.55)
      ..close();
    canvas.drawPath(fuselage, fill);

    // Main wing (swept back)
    final wing = Path()
      ..moveTo(w * 0.42, h * 0.55)
      ..lineTo(w * 0.30, h * 1.0)
      ..lineTo(w * 0.50, h * 1.0)
      ..lineTo(w * 0.62, h * 0.55)
      ..close();
    canvas.drawPath(wing, fill);

    // Tail wing
    final tail = Path()
      ..moveTo(w * 0.86, h * 0.47)
      ..lineTo(w * 0.98, h * 0.10)
      ..lineTo(w * 1.0, h * 0.14)
      ..lineTo(w * 0.93, h * 0.49)
      ..close();
    canvas.drawPath(tail, fill);

    // Nose tip highlight
    canvas.drawCircle(Offset(w * 0.03, h * 0.52), h * 0.05, fill);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
