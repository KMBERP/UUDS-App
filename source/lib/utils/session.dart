import '../models/models.dart';

/// Holds the currently signed-in inspector for as long as the app process
/// is alive.
///
/// The Home/Gallery/Reports screens are each full-screen routes that get
/// destroyed and recreated every time the bottom navigation bar switches
/// between them (see `AppBottomNav._go`, which uses `pushAndRemoveUntil`).
/// If the selected inspector only lived in `HomeScreen`'s own State object,
/// it would disappear the instant you left the Home tab and came back —
/// looking exactly like an unwanted logout.
///
/// `Session` lives outside any single screen's lifecycle, so switching tabs
/// never loses it. The inspector only actually gets logged out when the
/// user double-taps the back button on Home to log out on purpose (see
/// `HomeScreen`'s `PopScope`), or when the app process itself is killed —
/// in which case `HomeScreen` falls back to the last-saved inspector ID
/// persisted in the database.
class Session {
  Session._();

  static Employee? currentEmployee;

  static void login(Employee employee) {
    currentEmployee = employee;
  }

  static void logout() {
    currentEmployee = null;
  }
}
