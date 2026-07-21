import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider/path_provider.dart';

import '../providers/download_manager_provider.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('downloads_v2.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dbPath = await getApplicationSupportDirectory();
    final path = p.join(dbPath.path, filePath);

    return await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: _createDB,
      ),
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
CREATE TABLE downloads (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  url TEXT NOT NULL,
  filePath TEXT NOT NULL,
  thumbnailUrl TEXT NOT NULL,
  quality TEXT NOT NULL,
  platform TEXT NOT NULL,
  progress REAL NOT NULL,
  status INTEGER NOT NULL,
  createdAt TEXT NOT NULL,
  scheduledAt TEXT,
  completedAt TEXT,
  audioOutputFormat TEXT,
  videoOutputFormat TEXT NOT NULL,
  error TEXT,
  pageUrl TEXT NOT NULL,
  audioStreamUrl TEXT,
  connections INTEGER NOT NULL,
  retryCount INTEGER NOT NULL,
  phase TEXT,
  downloadedBytes INTEGER NOT NULL,
  totalBytes INTEGER NOT NULL,
  speedBytesSec INTEGER NOT NULL,
  etaSeconds INTEGER NOT NULL
)
''');
  }

  Future<void> insertOrUpdateDownload(DownloadItem item) async {
    final db = await instance.database;
    await db.insert(
      'downloads',
      item.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateDownload(DownloadItem item) async {
    final db = await instance.database;
    await db.update(
      'downloads',
      item.toJson(),
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  Future<List<DownloadItem>> getAllDownloads() async {
    final db = await instance.database;
    const orderBy = 'createdAt DESC';
    final result = await db.query('downloads', orderBy: orderBy);
    return result.map((json) => DownloadItem.fromJson(json)).toList();
  }

  Future<void> deleteDownload(String id) async {
    final db = await instance.database;
    await db.delete(
      'downloads',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
