import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'screens/splash_screen.dart';
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
  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await Permission.camera.request();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UUDS Aircraft Parts Inspection',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const SplashScreen(),
    );
  }
}
