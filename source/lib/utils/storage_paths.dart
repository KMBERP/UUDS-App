import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Everything to do with where UUDS photos/backups/reports live on disk.
///
/// Two locations are used together, on purpose:
///
/// 1. A private **working copy** under the app's own external files area
///    (`Android/data/<pkg>/files/UUDS/...`). No special runtime permission
///    is needed for this on ANY Android version, so it always works. This
///    is the copy the app itself reads from (Gallery tab, Reports, PDF
///    generation, backups) — reliable and guaranteed to exist.
/// 2. A **public mirror copy** written straight into the device's Pictures
///    folder via the Android MediaStore API (`publishToGallery`), organised
///    exactly as `Pictures/UUDS/<Aircraft>/<InspectionType>/<Location>/...`.
///    This is what makes photos show up immediately in the Gallery/Photos
///    app and any file manager, in the correct sub-folder. Using MediaStore
///    (instead of the old "All files access" permission) means no special
///    permission dialog is needed and the app stays compliant with Play
///    Store policy.
class StoragePaths {
  StoragePaths._();

  static const MethodChannel _mediaChannel = MethodChannel('uuds/photo_store');

  static String _sanitize(String s) => s.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '-');

  /// `Android/data/<pkg>/files/UUDS` — created if missing. Single source of
  /// truth for everything the app itself reads back.
  static Future<Directory> root() async {
    final base = await getExternalStorageDirectory();
    final dir = Directory('${base!.path}/UUDS');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// `UUDS / <Aircraft Reg> / <Inspection Type> / <Location>` working folder
  /// used to store the private, always-reliable copy of each photo.
  static Future<Directory> photoDirectory({
    required String aircraftReg,
    required String inspectionTypeLabel,
    required String location,
  }) async {
    final dir = Directory(
      '${(await root()).path}/${_sanitize(aircraftReg)}/${_sanitize(inspectionTypeLabel)}/${_sanitize(location)}',
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// UUDS / Backups
  static Future<Directory> backupsDirectory() async {
    final dir = Directory('${(await root()).path}/Backups');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// UUDS / Reports
  static Future<Directory> reportsDirectory() async {
    final dir = Directory('${(await root()).path}/Reports');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Mirrors an already-saved photo into the device's public Gallery via
  /// MediaStore, nested exactly as
  /// `Pictures/UUDS/<Aircraft>/<InspectionType>/<Location>/<fileName>`.
  /// Returns true if the mirror copy was written successfully. Failure here
  /// is non-fatal — the private working copy (used by the app itself) is
  /// always saved regardless of this result.
  static Future<bool> publishToGallery({
    required String sourcePath,
    required String aircraftReg,
    required String inspectionTypeLabel,
    required String location,
    required String fileName,
  }) async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _mediaChannel.invokeMethod<bool>('publishToGallery', {
        'sourcePath': sourcePath,
        'aircraft': _sanitize(aircraftReg),
        'type': _sanitize(inspectionTypeLabel),
        'location': _sanitize(location),
        'fileName': fileName,
      });
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }
}
