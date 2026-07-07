import 'package:flutter/material.dart';

const Color kPrimary = Color(0xFF0B3D91); // company navy blue
const Color kAccent = Color(0xFFE8A317); // amber accent
const Color kDispatch = Color(0xFFB0470A);
const Color kHeaderBlue = Color(0xFF4FC3F7); // bright blue for headings on dark backgrounds

List<BoxShadow> kRaisedShadow = [
  BoxShadow(
    color: kPrimary.withOpacity(0.30),
    offset: const Offset(0, 6),
    blurRadius: 14,
  ),
];

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: kPrimary,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: const Color(0xFFF2F4F8),
    appBarTheme: const AppBarTheme(
      backgroundColor: kPrimary,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 56),
        elevation: 6,
        shadowColor: kPrimary.withOpacity(0.5),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
    fontFamily: 'Roboto',
  );
}
