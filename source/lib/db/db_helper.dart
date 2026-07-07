import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/models.dart';
import '../utils/inspector_roster.dart';

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
      version: 4,
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
        await db.execute('''
          CREATE TABLE part_locations(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT UNIQUE NOT NULL
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
        for (final loc in [
          'Cockpit',
          'Forward Galley',
          'Aft Galley',
          'Forward Lavatory',
          'Aft Lavatory',
          'Cabin - Seat Row',
          'Cargo Bay',
          'Overhead Bin',
          'Sidewall Panel',
          'Divider / Partition',
        ]) {
          await db.insert('part_locations', {'name': loc});
        }
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
      },
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
    return Aircraft(id: id, regNo: regNo.trim());
  }

  Future<void> updateAircraft(int id, String newRegNo) async {
    final db = await database;
    await db.update('aircraft', {'regNo': newRegNo.trim()}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAircraft(int id) async {
    final db = await database;
    await db.delete('aircraft', where: 'id = ?', whereArgs: [id]);
  }

  // ---------- Part Locations ----------
  Future<List<PartLocation>> getPartLocations() async {
    final db = await database;
    final rows = await db.query('part_locations', orderBy: 'name ASC');
    return rows.map((e) => PartLocation.fromMap(e)).toList();
  }

  Future<PartLocation> addPartLocation(String name) async {
    final db = await database;
    final id = await db.insert('part_locations', {'name': name.trim()},
        conflictAlgorithm: ConflictAlgorithm.ignore);
    if (id == 0) {
      final existing = await db.query('part_locations', where: 'name = ?', whereArgs: [name.trim()]);
      return PartLocation.fromMap(existing.first);
    }
    return PartLocation(id: id, name: name.trim());
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
