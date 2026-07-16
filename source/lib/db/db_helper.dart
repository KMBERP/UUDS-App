import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/models.dart';
import '../utils/inspector_roster.dart';

/// The fixed set of part locations used by the app. Keep this list as the
/// single source of truth — both fresh installs (onCreate) and existing
/// installs (onUpgrade migration) seed from it.
const List<String> kDefaultPartLocations = [
  'LAV 3UE',
  'LAV 3UF',
  'LAV 3UG',
  'LAV 3UH',
  'LAV 5ML',
  'LAV 5MJ',
  'LAV 5MI',
  'LAV 5MK',
  'LAV 1UB',
  'LAV 1 MC',
  'LAV 2MM',
  'LAV 1MA',
  'LAV 3MH',
  'LAV 1MB',
  'LAV 3MG',
  'LAV 1UA',
];

class DBHelper {
  DBHelper._();
  static final DBHelper instance = DBHelper._();
  Database? _db;
  String? _dbPath;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<String> get dbFilePath async {
    await database;
    return _dbPath!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'uuds_parts.db');
    _dbPath = path;
    return openDatabase(
      path,
      version: 6,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE employees(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT UNIQUE NOT NULL,
            idNumber TEXT DEFAULT ''
          )
        ''');
        await db.execute('''
          CREATE TABLE aircraft(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            regNo TEXT UNIQUE NOT NULL
          )
        ''');
        // Each row belongs to exactly one aircraft (aircraftId), so adding,
        // renaming, or removing a location while working on one aircraft
        // can never affect any other aircraft's list.
        await db.execute('''
          CREATE TABLE part_locations(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            aircraftId INTEGER NOT NULL,
            name TEXT NOT NULL,
            UNIQUE(aircraftId, name)
          )
        ''');
        await db.execute('''
          CREATE TABLE settings(
            key TEXT PRIMARY KEY,
            value TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE photos(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            employeeName TEXT NOT NULL,
            aircraftReg TEXT NOT NULL,
            inspectionType TEXT NOT NULL,
            partLocation TEXT NOT NULL,
            filePath TEXT NOT NULL,
            timestamp TEXT NOT NULL,
            remarks TEXT DEFAULT '',
            tagPartNo TEXT DEFAULT '',
            tagDescription TEXT DEFAULT '',
            tagLocation TEXT DEFAULT '',
            tagQty TEXT DEFAULT ''
          )
        ''');
        // Note: part_locations is no longer seeded here - there's no
        // aircraft to attach a location to yet. Each aircraft gets its own
        // copy of kDefaultPartLocations the moment it's added; see
        // addAircraft() below.
        for (final entry in InspectorRoster.seed) {
          await db.insert('employees', {'name': entry.$1, 'idNumber': entry.$2},
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute("ALTER TABLE photos ADD COLUMN remarks TEXT DEFAULT ''");
        }
        if (oldVersion < 3) {
          await db.execute("ALTER TABLE photos ADD COLUMN tagPartNo TEXT DEFAULT ''");
          await db.execute("ALTER TABLE photos ADD COLUMN tagDescription TEXT DEFAULT ''");
          await db.execute("ALTER TABLE photos ADD COLUMN tagLocation TEXT DEFAULT ''");
        }
        if (oldVersion < 4) {
          await db.execute("ALTER TABLE employees ADD COLUMN idNumber TEXT DEFAULT ''");
          await db.execute("ALTER TABLE photos ADD COLUMN tagQty TEXT DEFAULT ''");
          for (final entry in InspectorRoster.seed) {
            await db.insert('employees', {'name': entry.$1, 'idNumber': entry.$2},
                conflictAlgorithm: ConflictAlgorithm.ignore);
          }
        }
        if (oldVersion < 5) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS settings(
              key TEXT PRIMARY KEY,
              value TEXT
            )
          ''');
          // Replace the old part-locations list with the new fixed set.
          await db.delete('part_locations');
          for (final loc in kDefaultPartLocations) {
            await db.insert('part_locations', {'name': loc},
                conflictAlgorithm: ConflictAlgorithm.ignore);
          }
        }
        if (oldVersion < 6) {
          // Part locations used to be one single shared table: editing,
          // renaming, or deleting a location while working on one aircraft
          // silently changed the list for every other aircraft too, because
          // they were all reading and writing the exact same rows. Give
          // each aircraft its own independent set of locations instead.
          final aircraftRows = await db.query('aircraft');
          final oldLocationRows = await db.query('part_locations');

          await db.execute('''
            CREATE TABLE part_locations_new(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              aircraftId INTEGER NOT NULL,
              name TEXT NOT NULL,
              UNIQUE(aircraftId, name)
            )
          ''');

          // Every aircraft that already existed keeps a full copy of
          // whatever was in the old shared list, so nobody loses a location
          // they were already using - it just becomes independently
          // editable per aircraft from here on.
          for (final ac in aircraftRows) {
            final aircraftId = ac['id'] as int;
            final namesToSeed = oldLocationRows.isNotEmpty
                ? oldLocationRows.map((r) => r['name'] as String)
                : kDefaultPartLocations;
            for (final name in namesToSeed) {
              await db.insert('part_locations_new', {'aircraftId': aircraftId, 'name': name},
                  conflictAlgorithm: ConflictAlgorithm.ignore);
            }
          }

          await db.execute('DROP TABLE part_locations');
          await db.execute('ALTER TABLE part_locations_new RENAME TO part_locations');

          // Paresh Abraham has left / should no longer appear as a
          // selectable inspector. Past photos already recorded under his
          // name are left untouched (they're just historical text, not a
          // reference to this row), only the active roster entry goes.
          await db.delete('employees', where: 'UPPER(TRIM(name)) = ?', whereArgs: ['PARESH ABRAHAM']);
        }
      },
    );
  }

  // ---------- Settings (small key/value store, e.g. last-used inspector) ----------
  Future<String?> getSetting(String key) async {
    final db = await database;
    final rows = await db.query('settings', where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ---------- Employees ----------
  Future<List<Employee>> getEmployees() async {
    final db = await database;
    final rows = await db.query('employees', orderBy: 'name ASC');
    return rows.map((e) => Employee.fromMap(e)).toList();
  }

  Future<Employee> addEmployee(String name, {String idNumber = ''}) async {
    final db = await database;
    final id = await db.insert('employees', {'name': name.trim(), 'idNumber': idNumber.trim()},
        conflictAlgorithm: ConflictAlgorithm.ignore);
    if (id == 0) {
      final existing = await db.query('employees', where: 'name = ?', whereArgs: [name.trim()]);
      return Employee.fromMap(existing.first);
    }
    return Employee(id: id, name: name.trim(), idNumber: idNumber.trim());
  }

  Future<void> updateEmployee(int id, String newName, {String? idNumber}) async {
    final db = await database;
    final values = <String, dynamic>{'name': newName.trim()};
    if (idNumber != null) values['idNumber'] = idNumber.trim();
    await db.update('employees', values, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteEmployee(int id) async {
    final db = await database;
    await db.delete('employees', where: 'id = ?', whereArgs: [id]);
  }

  /// Finds an employee by staff ID digits, tolerating leading zeros
  /// (e.g. "71" matches an ID stored as "071").
  Future<Employee?> getEmployeeByIdInput(String input) async {
    final digits = input.trim();
    if (digits.isEmpty) return null;
    final db = await database;
    final exact = await db.query('employees', where: 'idNumber = ?', whereArgs: [digits]);
    if (exact.isNotEmpty) return Employee.fromMap(exact.first);

    final n = int.tryParse(digits);
    if (n == null) return null;
    final all = await db.query('employees', where: "idNumber != ''");
    for (final row in all) {
      final key = int.tryParse(row['idNumber'] as String);
      if (key != null && key == n) return Employee.fromMap(row);
    }
    return null;
  }

  /// Returns employees whose staff ID starts with [prefix] (e.g. "4" matches
  /// "4", "47", "476"...), for use in a live suggestions dropdown while the
  /// user is typing an ID. Empty/blank prefixes return no suggestions.
  Future<List<Employee>> getEmployeesByIdPrefix(String prefix) async {
    final p = prefix.trim();
    if (p.isEmpty) return [];
    final db = await database;
    final rows = await db.query(
      'employees',
      where: "idNumber != '' AND idNumber LIKE ?",
      whereArgs: ['$p%'],
      orderBy: 'idNumber ASC',
      limit: 8,
    );
    return rows.map((e) => Employee.fromMap(e)).toList();
  }

  // ---------- Aircraft ----------
  Future<List<Aircraft>> getAircraft() async {
    final db = await database;
    final rows = await db.query('aircraft', orderBy: 'regNo ASC');
    return rows.map((e) => Aircraft.fromMap(e)).toList();
  }

  Future<Aircraft> addAircraft(String regNo) async {
    final db = await database;
    final id = await db.insert('aircraft', {'regNo': regNo.trim()},
        conflictAlgorithm: ConflictAlgorithm.ignore);
    if (id == 0) {
      final existing = await db.query('aircraft', where: 'regNo = ?', whereArgs: [regNo.trim()]);
      return Aircraft.fromMap(existing.first);
    }
    // Brand new aircraft: give it its own copy of the standard location
    // list to start from. From this point on, edits/additions/deletions
    // only ever touch this aircraft's own rows.
    for (final loc in kDefaultPartLocations) {
      await db.insert('part_locations', {'aircraftId': id, 'name': loc},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    return Aircraft(id: id, regNo: regNo.trim());
  }

  Future<void> updateAircraft(int id, String newRegNo) async {
    final db = await database;
    await db.update('aircraft', {'regNo': newRegNo.trim()}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAircraft(int id) async {
    final db = await database;
    await db.delete('aircraft', where: 'id = ?', whereArgs: [id]);
    await db.delete('part_locations', where: 'aircraftId = ?', whereArgs: [id]);
  }

  // ---------- Part Locations (each row belongs to one aircraft) ----------
  Future<List<PartLocation>> getPartLocations(int aircraftId) async {
    final db = await database;
    final rows = await db.query('part_locations',
        where: 'aircraftId = ?', whereArgs: [aircraftId], orderBy: 'name ASC');
    return rows.map((e) => PartLocation.fromMap(e)).toList();
  }

  /// Distinct location names used across every aircraft combined - for
  /// cross-aircraft filter UIs (like the backup selection dialog) that
  /// aren't about editing any one aircraft's own location list.
  Future<List<String>> getAllDistinctPartLocationNames() async {
    final db = await database;
    final rows = await db.query('part_locations', distinct: true, columns: ['name'], orderBy: 'name ASC');
    return rows.map((e) => e['name'] as String).toList();
  }

  Future<PartLocation> addPartLocation(int aircraftId, String name) async {
    final db = await database;
    final id = await db.insert('part_locations', {'aircraftId': aircraftId, 'name': name.trim()},
        conflictAlgorithm: ConflictAlgorithm.ignore);
    if (id == 0) {
      final existing = await db.query('part_locations',
          where: 'aircraftId = ? AND name = ?', whereArgs: [aircraftId, name.trim()]);
      return PartLocation.fromMap(existing.first);
    }
    return PartLocation(id: id, aircraftId: aircraftId, name: name.trim());
  }

  Future<void> updatePartLocation(int id, String newName) async {
    final db = await database;
    await db.update('part_locations', {'name': newName.trim()}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deletePartLocation(int id) async {
    final db = await database;
    await db.delete('part_locations', where: 'id = ?', whereArgs: [id]);
  }

  // ---------- Photos ----------
  Future<int> addPhoto(InspectionPhoto p) async {
    final db = await database;
    return db.insert('photos', p.toMap()..remove('id'));
  }

  Future<List<InspectionPhoto>> getPhotos({
    String? aircraftReg,
    String? inspectionType,
    String? partLocation,
    String? fromDate,
    String? toDate,
  }) async {
    final db = await database;
    final where = <String>[];
    final args = <dynamic>[];
    if (aircraftReg != null) {
      where.add('aircraftReg = ?');
      args.add(aircraftReg);
    }
    if (inspectionType != null) {
      where.add('inspectionType = ?');
      args.add(inspectionType);
    }
    if (partLocation != null) {
      where.add('partLocation = ?');
      args.add(partLocation);
    }
    if (fromDate != null) {
      where.add('timestamp >= ?');
      args.add(fromDate);
    }
    if (toDate != null) {
      where.add('timestamp <= ?');
      args.add(toDate);
    }
    final rows = await db.query(
      'photos',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: where.isEmpty ? null : args,
      orderBy: 'timestamp DESC',
    );
    return rows.map((e) => InspectionPhoto.fromMap(e)).toList();
  }

  Future<void> deletePhoto(int id) async {
    final db = await database;
    await db.delete('photos', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updatePhotoTagFields(
    int id,
    String partNo,
    String description,
    String location,
    String qty,
  ) async {
    final db = await database;
    await db.update(
      'photos',
      {'tagPartNo': partNo, 'tagDescription': description, 'tagLocation': location, 'tagQty': qty},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---------- Stats (for Home dashboard) ----------
  Future<Map<String, int>> getStats() async {
    final db = await database;
    final aircraftCount = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM aircraft')) ??
        0;
    final totalPhotos =
        Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM photos')) ?? 0;
    final todayPrefix = DateTime.now().toIso8601String().substring(0, 10);
    final todayPhotos = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM photos WHERE timestamp LIKE ?',
          ['$todayPrefix%'],
        )) ??
        0;
    final todayReceiving = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM photos WHERE timestamp LIKE ? AND inspectionType = ?',
          ['$todayPrefix%', 'Receiving'],
        )) ??
        0;
    final todayDispatch = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM photos WHERE timestamp LIKE ? AND inspectionType = ?',
          ['$todayPrefix%', 'Dispatch'],
        )) ??
        0;
    return {
      'aircraft': aircraftCount,
      'totalPhotos': totalPhotos,
      'todayPhotos': todayPhotos,
      'todayReceiving': todayReceiving,
      'todayDispatch': todayDispatch,
    };
  }
}
