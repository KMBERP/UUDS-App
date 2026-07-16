import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'screens/splash_screen.dart';
import 'utils/inactivity_guard.dart';
import 'utils/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const UudsPartsApp());
}

class UudsPartsApp extends StatefulWidget {
  const UudsPartsApp({super.key});

  @override
  State<UudsPartsApp> createState() => _UudsPartsAppState();
}

class _UudsPartsAppState extends State<UudsPartsApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await Permission.camera.request();
    // Photos are saved to the app's own private folder (no permission
    // needed on any Android version) and mirrored into the public Gallery
    // via the MediaStore API, which also needs no special permission —
    // so there's nothing further to request here.
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'UUDS Aircraft Parts Inspection',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const SplashScreen(),
      // Wrapping here (rather than around MaterialApp itself) puts the
      // guard inside the Navigator's overlay, so it sees touch activity on
      // every screen/route in the app, not just whichever one was current
      // when it was built.
      builder: (context, child) {
        return InactivityGuard(
          navigatorKey: _navigatorKey,
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
