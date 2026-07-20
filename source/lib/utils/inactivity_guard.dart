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
///
/// Implementation note: this tracks the real wall-clock time of the last
/// touch and checks elapsed time on a short recurring tick, rather than
/// relying on a single "fire once in exactly 10 minutes" Timer. A lone
/// delayed Timer can be delayed or silently dropped by Android if the
/// screen locks or the app is backgrounded for a while (battery-saving
/// throttling); comparing real timestamps on every tick, and again the
/// moment the app comes back to the foreground, keeps this correct even
/// if a tick or two gets delayed.
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

class _InactivityGuardState extends State<InactivityGuard> with WidgetsBindingObserver {
  DateTime _lastActivity = DateTime.now();
  Timer? _ticker;
  bool _loggingOut = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Check every 15s regardless of activity - cheap, and means the actual
    // logout never lags more than 15s behind the real 10-minute mark even
    // if nobody happens to touch the screen to re-trigger a check.
    _ticker = Timer.periodic(const Duration(seconds: 15), (_) => _checkIdle());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from the background/lock screen is exactly when a
    // throttled Timer could have been silently skipped, so check
    // immediately on resume rather than waiting for the next tick.
    if (state == AppLifecycleState.resumed) _checkIdle();
  }

  /// Called on every touch anywhere in the app.
  void _recordActivity() {
    _lastActivity = DateTime.now();
  }

  void _checkIdle() {
    if (_loggingOut || Session.currentEmployee == null) return;
    if (DateTime.now().difference(_lastActivity) >= widget.timeout) {
      _autoLogout();
    }
  }

  Future<void> _autoLogout() async {
    if (_loggingOut || Session.currentEmployee == null) return;
    _loggingOut = true;
    try {
      Session.logout();
      await DBHelper.instance.setSetting(Session.lastEmployeeIdKey, '');
      final nav = widget.navigatorKey.currentState;
      if (nav == null) return;
      nav.pushAndRemoveUntil(fadeSlideRoute(const HomeScreen()), (route) => false);
      ScaffoldMessenger.maybeOf(nav.context)?.showSnackBar(
        const SnackBar(content: Text('Logged out after 10 minutes of inactivity')),
      );
    } finally {
      _loggingOut = false;
      // Fresh clock for whoever uses the device next.
      _lastActivity = DateTime.now();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _recordActivity(),
      onPointerMove: (_) => _recordActivity(),
      onPointerUp: (_) => _recordActivity(),
      child: widget.child,
    );
  }
}
