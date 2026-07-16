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
/// `HomeScreen`'s `PopScope`), after 10 minutes of no touch activity
/// anywhere in the app (see `InactivityGuard`), or when the app process
/// itself is killed — in which case `HomeScreen` falls back to the
/// last-saved inspector ID persisted in the database.
class Session {
  Session._();

  /// Settings-table key the last-signed-in inspector's staff ID is saved
  /// under, shared between `HomeScreen` and `InactivityGuard` so both read
  /// and clear the exact same value.
  static const String lastEmployeeIdKey = 'lastEmployeeId';

  /// Staff IDs with admin rights (currently: bulk-deleting aircraft and
  /// part locations from the Aircraft/Part Location screens). Add more IDs
  /// here if additional admins are needed later.
  static const Set<String> _adminIds = {'476'};

  static Employee? currentEmployee;

  /// Whether the currently signed-in inspector has admin rights.
  static bool get isAdmin =>
      currentEmployee != null && _adminIds.contains(currentEmployee!.idNumber);

  static void login(Employee employee) {
    currentEmployee = employee;
  }

  static void logout() {
    currentEmployee = null;
  }
}
