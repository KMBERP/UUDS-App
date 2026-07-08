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
      version: 5, // Bumped to 5 for location reset
      onCreate: (db, version) async {
        await db.execute("""
          CREATE TABLE employees(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT UNIQUE NOT NULL,
            idNumber TEXT DEFAULT ''
          )
        """);
        await db.execute("""
          CREATE TABLE aircraft(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            regNo TEXT UNIQUE NOT NULL
          )
        """);
        await db.execute("""
          CREATE TABLE part_locations(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT UNIQUE NOT NULL
          )
        """);
        await db.execute("""
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
        """);
        await _seedDefaults(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 5) {
          // Clear old locations and seed new ones for version 5
          await db.delete('part_locations');
          await _seedDefaults(db);
        }
      },
    );
  }

  Future<void> _seedDefaults(Database db) async {
    // Seed employees from roster
    for (final entry in inspectorRoster.entries) {
      await db.insert(
        'employees',
        {'name': entry.value, 'idNumber': entry.key == entry.value ? '' : entry.key},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    // Seed new alphabetically sorted locations
    final locations = [
      'LAV 1 MC',
      'LAV 1MA',
      'LAV 1MB',
      'LAV 1UA',
      'LAV 1UB',
      'LAV 2MM',
      'LAV 3MG',
      'LAV 3MH',
      'LAV 3UE',
      'LAV 3UF',
      'LAV 3UG',
      'LAV 3UH',
      'LAV 5MI',
      'LAV 5MJ',
      'LAV 5MK',
      'LAV 5ML',
    ];
    for (final loc in locations) {
      await db.insert('part_locations', {'name': loc}, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<int> addEmployee(String name, {String idNumber = ''}) async {
    final db = await database;
    return db.insert('employees', {'name': name, 'idNumber': idNumber});
  }

  Future<void> updateEmployee(int id, String name, {String idNumber = ''}) async {
    final db = await database;
    await db.update('employees', {'name': name, 'idNumber': idNumber}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteEmployee(int id) async {
    final db = await database;
    await db.delete('employees', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Employee>> getEmployees() async {
    final db = await database;
    final maps = await db.query('employees', orderBy: 'name ASC');
    return maps.map((m) => Employee.fromMap(m)).toList();
  }

  Future<Employee?> getEmployeeByIdInput(String input) async {
    final db = await database;
    final maps = await db.query(
      'employees',
      where: 'idNumber = ? OR name = ?',
      whereArgs: [input, input],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Employee.fromMap(maps.first);
  }

  Future<List<Employee>> getEmployeesByIdPrefix(String prefix) async {
    final db = await database;
    final maps = await db.query(
      'employees',
      where: 'idNumber LIKE ?',
      whereArgs: ['$prefix%'],
      orderBy: 'idNumber ASC',
    );
    return maps.map((m) => Employee.fromMap(m)).toList();
  }

  Future<int> addAircraft(String regNo) async {
    final db = await database;
    return db.insert('aircraft', {'regNo': regNo});
  }

  Future<List<Aircraft>> getAircraft() async {
    final db = await database;
    final maps = await db.query('aircraft', orderBy: 'regNo ASC');
    return maps.map((m) => Aircraft.fromMap(m)).toList();
  }

  Future<int> addPartLocation(String name) async {
    final db = await database;
    return db.insert('part_locations', {'name': name});
  }

  Future<List<PartLocation>> getPartLocations() async {
    final db = await database;
    final maps = await db.query('part_locations', orderBy: 'name ASC');
    return maps.map((m) => PartLocation.fromMap(m)).toList();
  }

  Future<int> insertPhoto(InspectionPhoto photo) async {
    final db = await database;
    return db.insert('photos', photo.toMap());
  }

  Future<List<InspectionPhoto>> getPhotos({String? fromDate, String? toDate}) async {
    final db = await database;
    String? where;
    List<String>? whereArgs;
    if (fromDate != null && toDate != null) {
      where = 'timestamp >= ? AND timestamp <= ?';
      whereArgs = [fromDate, toDate];
    }
    final maps = await db.query('photos', where: where, whereArgs: whereArgs, orderBy: 'timestamp DESC');
    return maps.map((m) => InspectionPhoto.fromMap(m)).toList();
  }

  Future<void> deletePhoto(int id) async {
    final db = await database;
    await db.delete('photos', where: 'id = ?', whereArgs: [id]);
  }

  Future<Map<String, int>> getStats() async {
    final db = await database;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day).toIso8601String();
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59).toIso8601String();

    final aircraftCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(DISTINCT aircraftReg) FROM photos')) ?? 0;
    final totalPhotos = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM photos')) ?? 0;
    final todayPhotos = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM photos WHERE timestamp >= ? AND timestamp <= ?',
      [todayStart, todayEnd],
    )) ?? 0;
    final todayReceiving = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM photos WHERE inspectionType = ? AND timestamp >= ? AND timestamp <= ?',
      ['Receiving', todayStart, todayEnd],
    )) ?? 0;
    final todayDispatch = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM photos WHERE inspectionType = ? AND timestamp >= ? AND timestamp <= ?',
      ['Dispatch', todayStart, todayEnd],
    )) ?? 0;

    return {
      'aircraft': aircraftCount,
      'totalPhotos': totalPhotos,
      'todayPhotos': todayPhotos,
      'todayReceiving': todayReceiving,
      'todayDispatch': todayDispatch,
    };
  }
}
