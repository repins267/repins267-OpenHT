// lib/services/repeater_cache.dart
// Local SQLite cache for repeater data - enables offline Near Repeater function

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/repeater.dart';

class RepeaterCache {
  static Database? _db;
  static const String _tableName = 'repeaters';
  static const String _metaTable = 'cache_meta';

  // Cache expires after 7 days to stay current with RepeaterBook
  static const Duration cacheExpiry = Duration(days: 7);

  Future<Database> get db async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'openht_repeaters.db');

    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_tableName (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sysname TEXT NOT NULL,
            frequency REAL NOT NULL,
            input_freq REAL,
            offset TEXT,
            tone TEXT,
            dtcs TEXT,
            tone_mode TEXT,
            callsign TEXT,
            city TEXT,
            state TEXT,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            distance_miles REAL,
            use TEXT,
            operational TEXT,
            modes TEXT,
            notes TEXT,
            cached_at INTEGER NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE $_metaTable (
            key TEXT PRIMARY KEY,
            value TEXT,
            updated_at INTEGER
          )
        ''');

        // Index for fast geospatial bounding box queries
        await db.execute('''
          CREATE INDEX idx_lat_lon ON $_tableName (latitude, longitude)
        ''');
      },
    );
  }

  /// Store repeaters fetched near a location
  Future<void> cacheRepeaters(List<Repeater> repeaters) async {
    final database = await db;
    final now = DateTime.now().millisecondsSinceEpoch;

    final batch = database.batch();
    for (final r in repeaters) {
      final map = r.toMap()..['cached_at'] = now;
      batch.insert(
        _tableName,
        map,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Query cached repeaters within a bounding box around [lat]/[lon].
  /// Falls back gracefully if cache is stale or empty.
  Future<List<Repeater>> queryNearby({
    required double lat,
    required double lon,
    double radiusMiles = 50,
    bool includeStale = false,
  }) async {
    final database = await db;

    // Approx bounding box: 1 degree lat ≈ 69 miles, 1 degree lon varies
    final latDelta = radiusMiles / 69.0;
    final lonDelta = radiusMiles / (69.0 * _cosLat(lat));

    final minLat = lat - latDelta;
    final maxLat = lat + latDelta;
    final minLon = lon - lonDelta;
    final maxLon = lon + lonDelta;

    String whereClause =
        'latitude BETWEEN ? AND ? AND longitude BETWEEN ? AND ?';
    final args = <dynamic>[minLat, maxLat, minLon, maxLon];

    if (!includeStale) {
      final cutoff = DateTime.now()
          .subtract(cacheExpiry)
          .millisecondsSinceEpoch;
      whereClause += ' AND cached_at > ?';
      args.add(cutoff);
    }

    final rows = await database.query(
      _tableName,
      where: whereClause,
      whereArgs: args,
      orderBy: 'distance_miles ASC',
    );

    return rows.map(Repeater.fromMap).toList();
  }

  /// Record that a region was fetched (for cache invalidation logic)
  Future<void> setMeta(String key, String value) async {
    final database = await db;
    await database.insert(
      _metaTable,
      {
        'key': key,
        'value': value,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getMeta(String key) async {
    final database = await db;
    final rows =
        await database.query(_metaTable, where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<int> getCachedCount() async {
    final database = await db;
    final result =
        await database.rawQuery('SELECT COUNT(*) as c FROM $_tableName');
    return (result.first['c'] as int?) ?? 0;
  }

  Future<void> clearAll() async {
    final database = await db;
    await database.delete(_tableName);
    await database.delete(_metaTable);
  }

  static double _cosLat(double lat) {
    // Degrees to radians
    final rad = lat * 3.141592653589793 / 180.0;
    return _cos(rad);
  }

  static double _cos(double x) {
    // Simple Taylor approximation adequate for our bounding box use
    double result = 1;
    double term = 1;
    for (int i = 1; i <= 8; i++) {
      term *= -x * x / ((2 * i - 1) * (2 * i));
      result += term;
    }
    return result.clamp(-1.0, 1.0);
  }
}
