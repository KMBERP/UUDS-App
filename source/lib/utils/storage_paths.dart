import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// Everything to do with where UUDS photos/backups/reports live on disk.
///
/// Photos are saved directly under the device's public Pictures folder
/// (`/storage/emulated/0/Pictures/UUDS/...`) rather than the app's private
/// sandbox (`Android/data/...`). That means:
///   - They show up in the normal Gallery/Photos app and any file manager.
///   - They are NOT deleted if the app is uninstalled (public storage is
///     untouched by uninstalling the app that created it).
///   - They're organised as UUDS > Aircraft > Inspection Type > Location,
///     exactly matching how they're browsed in the app.
class StoragePaths {
  StoragePaths._();

  /// Requests the broad "manage external storage" permission needed on
  /// Android 11+ to write into a custom nested folder structure under the
  /// public Pictures directory. Returns true if writing to public storage
  /// is available; false means callers should fall back to the app's
  /// private folder so capture still works even if the user declines.
  static Future<bool> ensurePublicStorageAccess() async {
    if (!Platform.isAndroid) return false;
    try {
      var status = await Permission.manageExternalStorage.status;
      if (status.isGranted) return true;
      status = await Permission.manageExternalStorage.request();
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> hasPublicStorageAccess() async {
    if (!Platform.isAndroid) return false;
    try {
      return (await Permission.manageExternalStorage.status).isGranted;
    } catch (_) {
      return false;
    }
  }

  /// `/storage/emulated/0/Pictures/UUDS` — created if missing.
  static Future<Directory> publicRoot() async {
    final dir = Directory('/storage/emulated/0/Pictures/UUDS');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Fallback root used only if public storage access isn't available
  /// (permission declined). This lives inside the app's own sandbox and
  /// WILL be removed on uninstall — public storage above is always
  /// preferred when possible.
  static Future<Directory> fallbackRoot() async {
    final base = await getExternalStorageDirectory();
    final dir = Directory('${base!.path}/UUDS_Aero_Photos');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static String _sanitize(String s) => s.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '-');

  /// UUDS / {AircraftReg} / {InspectionType} / {Location} / Foto
  static Future<Directory> photoDirectory({
    required String aircraftReg,
    required String inspectionTypeLabel,
    required String location,
  }) async {
    final hasAccess = await hasPublicStorageAccess();
    final root = hasAccess ? await publicRoot() : await fallbackRoot();
    final dir = Directory(
      '${root.path}/${_sanitize(aircraftReg)}/${_sanitize(inspectionTypeLabel)}/${_sanitize(location)}/Foto',
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// UUDS / Backups
  static Future<Directory> backupsDirectory() async {
    final hasAccess = await hasPublicStorageAccess();
    final root = hasAccess ? await publicRoot() : await fallbackRoot();
    final dir = Directory('${root.path}/Backups');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// UUDS / Reports
  static Future<Directory> reportsDirectory() async {
    final hasAccess = await hasPublicStorageAccess();
    final root = hasAccess ? await publicRoot() : await fallbackRoot();
    final dir = Directory('${root.path}/Reports');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }
}
