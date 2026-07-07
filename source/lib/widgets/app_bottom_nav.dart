import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../screens/home_screen.dart';
import '../screens/gallery_screen.dart';
import '../screens/reports_screen.dart';
import '../utils/page_transitions.dart';
import '../utils/theme.dart';

enum AppTab { home, gallery, reports }

/// Persistent bottom navigation shown across the main screens, with a
/// small blinking/colour-changing developer credit above it.
class AppBottomNav extends StatelessWidget {
  final AppTab current;
  const AppBottomNav({super.key, required this.current});

  void _go(BuildContext context, AppTab tab) {
    if (tab == current) return;
    late Widget page;
    switch (tab) {
      case AppTab.home:
        page = const HomeScreen();
        break;
      case AppTab.gallery:
        page = const GalleryScreen();
        break;
      case AppTab.reports:
        page = const ReportsScreen();
        break;
    }
    Navigator.of(context).pushAndRemoveUntil(
      fadeSlideRoute(page),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.12), offset: const Offset(0, -3), blurRadius: 10),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: _BlinkingCredit(),
            ),
            SizedBox(
              height: 60,
              child: Row(
                children: [
                  _navItem(context, AppTab.home, Icons.home_rounded, 'Home'),
                  _navItem(context, AppTab.gallery, Icons.photo_library_rounded, 'Gallery'),
                  _navItem(context, AppTab.reports, Icons.summarize_rounded, 'Reports'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navItem(BuildContext context, AppTab tab, IconData icon, String label) {
    final active = tab == current;
    return Expanded(
      child: InkWell(
        onTap: () => _go(context, tab),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: active ? kPrimary : Colors.black38, size: 24),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: active ? kPrimary : Colors.black38,
                fontSize: 11,
                fontWeight: active ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlinkingCredit extends StatefulWidget {
  const _BlinkingCredit();

  @override
  State<_BlinkingCredit> createState() => _BlinkingCreditState();
}

class _BlinkingCreditState extends State<_BlinkingCredit> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 5))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final color = HSVColor.fromAHSV(1.0, t * 360, 0.6, 0.7).toColor();
        final opacity = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(t * 2 * math.pi * 3));
        return Opacity(
          opacity: opacity,
          child: Text(
            'Developed by Khurram Munir Basra',
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: color),
          ),
        );
      },
    );
  }
}
