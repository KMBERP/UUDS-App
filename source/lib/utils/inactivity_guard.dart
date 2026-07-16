import 'dart:async';
import 'package:flutter/material.dart';
import '../db/db_helper.dart';
import '../screens/home_screen.dart';
import 'page_transitions.dart';
import 'session.dart';

/// Wraps the whole app (see `main.dart`'s `MaterialApp.builder`) and
/// automatically signs the inspector out after [timeout] with no touch
/// activity anywhere on screen — tapping, scrolling, dragging, taking a
/// photo, all count and push the clock back out.
///
/// This mirrors the manual double-back-press logout already on Home: both
/// paths call `Session.logout()`, clear the saved staff ID, and land back
/// on a fresh Home screen with no inspector selected. A shared/unattended
/// device never stays signed in under someone's name indefinitely.
class InactivityGuard extends StatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;
  final Duration timeout;

  const InactivityGuard({
    super.key,
    required this.child,
    required this.navigatorKey,
    this.timeout = const Duration(minutes: 10),
  });

  @override
  State<InactivityGuard> createState() => _InactivityGuardState();
}

class _InactivityGuardState extends State<InactivityGuard> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _armTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Called on every touch anywhere in the app. Just restarts a single
  /// Timer - cheap, no per-frame work.
  void _onActivity() => _armTimer();

  void _armTimer() {
    _timer?.cancel();
    _timer = Timer(widget.timeout, _autoLogout);
  }

  Future<void> _autoLogout() async {
    if (Session.currentEmployee == null) return; // nobody signed in - nothing to do
    Session.logout();
    await DBHelper.instance.setSetting(Session.lastEmployeeIdKey, '');
    final nav = widget.navigatorKey.currentState;
    if (nav == null) return;
    nav.pushAndRemoveUntil(fadeSlideRoute(const HomeScreen()), (route) => false);
    final ctx = nav.context;
    ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(
      const SnackBar(content: Text('Logged out after 10 minutes of inactivity')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _onActivity(),
      onPointerMove: (_) => _onActivity(),
      onPointerUp: (_) => _onActivity(),
      child: widget.child,
    );
  }
}
