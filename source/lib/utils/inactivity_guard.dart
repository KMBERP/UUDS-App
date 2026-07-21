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
/// Two things make this robust against Android backgrounding/killing the
/// app process, which a naive "single delayed Timer" approach isn't:
/// 1. A real-timestamp comparison on a recurring 15-second tick (and again
///    the moment the app returns to the foreground) instead of trusting a
///    lone Timer to fire at exactly the right moment - a background app
///    can have its timers throttled or paused by the OS for a while.
/// 2. The last-activity timestamp is also persisted to disk
///    (`Session.lastActivityKey`). If Android kills the whole app process
///    while it's backgrounded (likely once it's sat unused a while), this
///    in-memory guard dies with it - so on the next cold start, before
///    `HomeScreen` restores whichever inspector was last saved, it checks
///    this persisted timestamp itself and skips the restore if the app's
///    really been untouched for longer than the timeout. See
///    `HomeScreen._restoreLastEmployee`.
class InactivityGuard extends StatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;
  final Duration timeout;

  const InactivityGuard({
    super.key,
    required this.child,
    required this.navigatorKey,
    this.timeout = Session.inactivityTimeout,
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
    // if nobody happens to touch the screen to re-trigger a check. Also
    // doubles as the point where the last-activity timestamp gets synced
    // to disk (see class doc).
    _ticker = Timer.periodic(const Duration(seconds: 15), (_) => _tick());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Coming back from the background/lock screen is exactly when a
      // throttled Timer could have been silently skipped, so check
      // immediately on resume rather than waiting for the next tick.
      _tick();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      // About to go to the background (or be torn down) - make sure the
      // on-disk timestamp is current in case the process gets killed
      // outright while backgrounded, so a cold-started HomeScreen can
      // still tell how long it's really been.
      _persistLastActivity();
    }
  }

  /// Called on every touch anywhere in the app.
  void _recordActivity() {
    _lastActivity = DateTime.now();
  }

  void _tick() {
    _checkIdle();
    if (Session.currentEmployee != null) _persistLastActivity();
  }

  void _checkIdle() {
    if (_loggingOut || Session.currentEmployee == null) return;
    if (DateTime.now().difference(_lastActivity) >= widget.timeout) {
      _autoLogout();
    }
  }

  Future<void> _persistLastActivity() async {
    try {
      await DBHelper.instance.setSetting(Session.lastActivityKey, _lastActivity.toIso8601String());
    } catch (_) {
      // Best-effort - if this write fails, the cold-start check in
      // HomeScreen will just see a stale/missing timestamp and log out to
      // be safe rather than silently staying signed in.
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
