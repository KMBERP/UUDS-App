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
    final photosRoot = await StoragePaths.root();
    final backupsDir = await StoragePaths.backupsDirectory();

    final dbPath = await DBHelper.instance.dbFilePath;
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final zipPath = '${backupsDir.path}/UUDS_Backup_$stamp.zip';

    final archive = Archive();

    Future<void> scanAndAdd(Directory dir) async {
      if (!await dir.exists()) return;
      await for (final entity in dir.list()) {
        if (entity is! Directory) continue;
        final name = p.basename(entity.path);
        if (name == 'Backups' || name == 'Reports') continue;

        if (name == 'Photos' || name == 'Part_Tags') {
          await scanAndAdd(entity);
          continue;
        }

        if (!aircraftRegs.contains(name)) continue;

        await for (final typeEntity in entity.list()) {
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

    if (await photosRoot.exists()) {
      await scanAndAdd(photosRoot);
    }

    final dbFile = File(dbPath);
    if (await dbFile.exists()) {
      final dbBytes = await dbFile.readAsBytes();
      archive.addFile(ArchiveFile('uuds_parts_database.db', dbBytes.length, dbBytes));
    }

    final zipData = ZipEncoder().encode(archive);
    if (zipData != null) {
      await File(zipPath).writeAsBytes(zipData);
      // Also mirror to public Download and Pictures folders so it's guaranteed to survive uninstall
      await _mirrorBackupToPublicStorage(zipPath, stamp);
    }

    await Share.shareXFiles([XFile(zipPath)], text: 'UUDS Aero DWC - Backup ($stamp)');
    return zipPath;
  }

  /// Mirrors backup zip to public storage so it survives app uninstall
  static Future<void> _mirrorBackupToPublicStorage(String zipPath, String stamp) async {
    try {
      final bytes = await File(zipPath).readAsBytes();
      final publicDirs = [
        Directory('/storage/emulated/0/Download'),
        Directory('/storage/emulated/0/Pictures/UUDS/Backups'),
      ];
      for (final pDir in publicDirs) {
        try {
          if (!await pDir.exists()) await pDir.create(recursive: true);
          final target = File('${pDir.path}/UUDS_Backup_$stamp.zip');
          await target.writeAsBytes(bytes);
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// Scans for UUDS_Backup_*.zip files across phone storage
  static Future<List<File>> findAvailableBackups() async {
    final List<File> backups = [];
    final Set<String> seenNames = {};
    final List<String> searchDirs = [
      '/storage/emulated/0/Download',
      '/storage/emulated/0/Downloads',
      '/storage/emulated/0/Pictures/UUDS/Backups',
      '/storage/emulated/0/Pictures/UUDS',
      '/storage/emulated/0/Documents',
    ];

    try {
      final appBackupDir = await StoragePaths.backupsDirectory();
      searchDirs.insert(0, appBackupDir.path);
    } catch (_) {}

    for (final dirPath in searchDirs) {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) continue;
      try {
        final list = dir.listSync();
        for (final entity in list) {
          if (entity is File && entity.path.toLowerCase().endsWith('.zip')) {
            final bName = p.basename(entity.path);
            if ((bName.startsWith('UUDS_Backup') || bName.contains('UUDS')) && !seenNames.contains(bName)) {
              seenNames.add(bName);
              backups.add(entity);
            }
          }
        }
      } catch (_) {}
    }
    backups.sort((a, b) {
      try {
        return b.lastModifiedSync().compareTo(a.lastModifiedSync());
      } catch (_) {
        return 0;
      }
    });
    return backups;
  }

  /// Restores database and photos from a backup zip file
  static Future<bool> restoreFromZip(File zipFile) async {
    try {
      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      ArchiveFile? dbArchiveFile;
      for (final file in archive) {
        if (file.name == 'uuds_parts_database.db' || file.name.endsWith('.db')) {
          dbArchiveFile = file;
          break;
        }
      }

      if (dbArchiveFile == null) return false;

      // Close current DB connection before overwriting
      await DBHelper.instance.close();

      final dbPath = await DBHelper.instance.dbFilePath;
      final dbFile = File(dbPath);
      await dbFile.parent.create(recursive: true);
      await dbFile.writeAsBytes(dbArchiveFile.content as List<int>);

      // Restore photos into working storage
      final photosRoot = await StoragePaths.root();
      for (final file in archive) {
        if (file.name.startsWith('UUDS_Aero_Photos/') && !file.name.endsWith('/')) {
          final relPath = file.name.substring('UUDS_Aero_Photos/'.length);
          final target = File('${photosRoot.path}/$relPath');
          if (!target.existsSync()) {
            target.parent.createSync(recursive: true);
            target.writeAsBytesSync(file.content as List<int>);
          }
        }
      }

      // Reopen DB, run migrations (v9, v10)
      await DBHelper.instance.database;
      await DBHelper.instance.cleanExistingTagOcrData();
      await DBHelper.instance.sanitizeExistingPartLocations();
      return true;
    } catch (_) {
      return false;
    }
  }
}
