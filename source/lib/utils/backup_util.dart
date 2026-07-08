import 'dart:io';
import 'package:archive/archive.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import '../db/db_helper.dart';
import 'storage_paths.dart';

class BackupUtil {
  /// Creates a zip containing only the selected aircraft/location photo
  /// folders (plus the full database for safety), saves it under
  /// UUDS/Backups/ in public storage (grab it via USB cable + file manager
  /// on a PC, and it survives an app uninstall), and opens the share sheet
  /// so it can also be sent to Drive, WhatsApp, etc.
  static Future<String> createSelectiveBackupAndShare(
    Set<String> aircraftRegs,
    Set<String> locations,
  ) async {
    final hasAccess = await StoragePaths.hasPublicStorageAccess();
    final photosRoot = hasAccess ? await StoragePaths.publicRoot() : await StoragePaths.fallbackRoot();
    final backupsDir = await StoragePaths.backupsDirectory();

    final dbPath = await DBHelper.instance.dbFilePath;
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final zipPath = '${backupsDir.path}/UUDS_Backup_$stamp.zip';

    final archive = Archive();

    if (await photosRoot.exists()) {
      await for (final aircraftEntity in photosRoot.list()) {
        if (aircraftEntity is! Directory) continue;
        final aircraftName = p.basename(aircraftEntity.path);
        if (aircraftName == 'Backups' || aircraftName == 'Reports') continue;
        if (!aircraftRegs.contains(aircraftName)) continue;

        await for (final typeEntity in aircraftEntity.list()) {
          if (typeEntity is! Directory) continue;

          await for (final locEntity in typeEntity.list()) {
            if (locEntity is! Directory) continue;
            final locName = p.basename(locEntity.path);
            if (!locations.contains(locName)) continue;

            await for (final fileEntity in locEntity.list(recursive: true)) {
              if (fileEntity is File) {
                final relPath = fileEntity.path.substring(photosRoot.path.length + 1);
                final bytes = await fileEntity.readAsBytes();
                archive.addFile(ArchiveFile('UUDS_Aero_Photos/$relPath', bytes.length, bytes));
              }
            }
          }
        }
      }
    }

    final dbFile = File(dbPath);
    if (await dbFile.exists()) {
      final dbBytes = await dbFile.readAsBytes();
      archive.addFile(ArchiveFile('uuds_parts_database.db', dbBytes.length, dbBytes));
    }

    final zipData = ZipEncoder().encode(archive);
    if (zipData != null) {
      await File(zipPath).writeAsBytes(zipData);
    }

    await Share.shareXFiles([XFile(zipPath)], text: 'UUDS Aero DWC - Backup ($stamp)');
    return zipPath;
  }
}
