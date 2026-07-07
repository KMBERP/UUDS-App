import 'dart:io';
import 'package:archive/archive.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../db/db_helper.dart';

class BackupUtil {
  /// Creates a zip containing only the selected aircraft/location photo
  /// folders (plus the full database for safety), saves it under
  /// .../Backups/ (grab it via USB cable + file manager on a PC), and
  /// opens the share sheet so it can also be sent to Drive, WhatsApp, etc.
  static Future<String> createSelectiveBackupAndShare(
    Set<String> aircraftRegs,
    Set<String> locations,
  ) async {
    final base = await getExternalStorageDirectory();
    final photosRoot = Directory('${base!.path}/UUDS_Aero_Photos');
    final backupsDir = Directory('${base.path}/Backups');
    if (!await backupsDir.exists()) await backupsDir.create(recursive: true);

    final dbPath = await DBHelper.instance.dbFilePath;
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final zipPath = '${backupsDir.path}/UUDS_Backup_$stamp.zip';

    final archive = Archive();

    if (await photosRoot.exists()) {
      await for (final aircraftEntity in photosRoot.list()) {
        if (aircraftEntity is! Directory) continue;
        final aircraftName = p.basename(aircraftEntity.path);
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
