import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class SessionService {
  static const String _rootDir = 'lot-builder';

  Future<Directory> get rootDirectory async {
    final ext = await getExternalStorageDirectory();
    final storageRoot = ext!.parent.parent.parent.parent;
    final dir = Directory('${storageRoot.path}/Documents/$_rootDir');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<bool> requestStoragePermission() async {
    if (await Permission.manageExternalStorage.isGranted) return true;
    final status = await Permission.manageExternalStorage.request();
    return status.isGranted;
  }

  // ─── Auctions ─────────────────────────────────────────────────────────────

  Future<List<AuctionFolder>> listAuctions() async {
    final root = await rootDirectory;
    final dirs = root.listSync().whereType<Directory>().toList();
    dirs.sort((a, b) => b.path.compareTo(a.path)); // newest first

    final auctions = <AuctionFolder>[];
    for (final dir in dirs) {
      final jsonFile = File('${dir.path}/auction.json');
      if (await jsonFile.exists()) {
        String name = '';
        try {
          final data =
              jsonDecode(await jsonFile.readAsString()) as Map<String, dynamic>;
          name = data['name'] as String? ?? '';
        } catch (_) {}
        auctions.add(AuctionFolder(
          path: dir.path,
          name: dir.path.split(RegExp(r'[/\\]')).last,
          displayName: name,
        ));
      }
    }
    return auctions;
  }

  Future<AuctionFolder> createAuction({String name = ''}) async {
    final root = await rootDirectory;
    final timestamp = _timestamp();
    final slug = _slugify(name).isNotEmpty ? _slugify(name) : 'auction';
    final dir = Directory('${root.path}/${slug}_$timestamp');
    await dir.create();
    await File('${dir.path}/auction.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'name': name,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      }),
      flush: true,
    );
    return AuctionFolder(
      path: dir.path,
      name: dir.path.split(RegExp(r'[/\\]')).last,
      displayName: name,
    );
  }

  Future<void> deleteAuction(String folderPath) async {
    final dir = Directory(folderPath);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  // ─── Sessions ─────────────────────────────────────────────────────────────

  Future<List<SessionFolder>> listSessions(String auctionPath) async {
    final dir = Directory(auctionPath);
    final dirs = dir.listSync().whereType<Directory>().toList();
    dirs.sort((a, b) => a.path.compareTo(b.path)); // oldest first = natural order

    final sessions = <SessionFolder>[];
    for (final d in dirs) {
      final jsonFile = File('${d.path}/session.json');
      if (await jsonFile.exists()) {
        String displayName = '';
        int photoCount = 0;
        try {
          final data =
              jsonDecode(await jsonFile.readAsString()) as Map<String, dynamic>;
          displayName = data['name'] as String? ?? '';
          final lots = data['lots'] as List? ?? [];
          photoCount = lots.fold<int>(
              0, (sum, lot) => sum + ((lot['images'] as List?)?.length ?? 0));
        } catch (_) {}
        sessions.add(SessionFolder(
          path: d.path,
          name: d.path.split(RegExp(r'[/\\]')).last,
          displayName: displayName,
          photoCount: photoCount,
        ));
      }
    }
    return sessions;
  }

  Future<SessionData> createSession(
    String auctionPath, {
    String name = '',
    String deviceId = 'device01',
    int sessionNumber = 1,
  }) async {
    final timestamp = _timestamp();
    final label = name.isNotEmpty ? name : 'Session $sessionNumber';
    final slug = _slugify(label).isNotEmpty ? _slugify(label) : 'session';
    final dir = Directory('$auctionPath/${timestamp}_$slug');
    await dir.create();

    final json = {
      'version': '2.0',
      'session_id': 'sess_$timestamp',
      'captured_at': DateTime.now().toUtc().toIso8601String(),
      'name': label,
      'device': deviceId,
      'lots': <dynamic>[],
    };
    final session = SessionData(folderPath: dir.path, json: json);
    await _writeJson(session);
    return session;
  }

  Future<SessionData> loadSession(String sessionPath) async {
    final jsonFile = File('$sessionPath/session.json');
    final contents = await jsonFile.readAsString();
    return SessionData(
      folderPath: sessionPath,
      json: jsonDecode(contents),
    );
  }

  Future<void> deleteSession(String folderPath) async {
    final dir = Directory(folderPath);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  // ─── Lots ─────────────────────────────────────────────────────────────────

  Future<SessionData> addLot(SessionData session) async {
    session.lots.add({'images': <dynamic>[], 'notes': ''});
    await _writeJson(session);
    return session;
  }

  Future<SessionData> insertLot(SessionData session, int afterIndex) async {
    session.lots
        .insert(afterIndex + 1, {'images': <dynamic>[], 'notes': ''});
    await _writeJson(session);
    return session;
  }

  Future<SessionData> removeLot(SessionData session, int lotIndex) async {
    session.lots.removeAt(lotIndex);
    await _writeJson(session);
    return session;
  }

  Future<SessionData> splitLot(
      SessionData session, int lotIndex, int splitAtIndex) async {
    final lot = session.lots[lotIndex] as Map<String, dynamic>;
    final images = (lot['images'] as List).cast<String>();
    lot['images'] = images.sublist(0, splitAtIndex);
    session.lots.insert(lotIndex + 1, {
      'images': images.sublist(splitAtIndex),
      'notes': '',
    });
    await _writeJson(session);
    return session;
  }

  Future<SessionData> cleanEmptyLastLot(SessionData session) async {
    if (session.lots.isEmpty) return session;
    final last = session.lots.last as Map<String, dynamic>;
    if ((last['images'] as List).isEmpty) {
      session.lots.removeLast();
      await _writeJson(session);
    }
    return session;
  }

  // ─── Images ───────────────────────────────────────────────────────────────

  Future<SessionData> addImage(
      SessionData session, int lotIndex, String filename) async {
    final lot = session.lots[lotIndex] as Map<String, dynamic>;
    (lot['images'] as List).add(filename);
    await _writeJson(session);
    return session;
  }

  Future<SessionData> deleteImage(
      SessionData session, int lotIndex, int imageIndex) async {
    final lot = session.lots[lotIndex] as Map<String, dynamic>;
    final images = lot['images'] as List;
    final filename = images[imageIndex] as String;
    final file = File('${session.folderPath}/$filename');
    if (await file.exists()) await file.delete();
    images.removeAt(imageIndex);
    await _writeJson(session);
    return session;
  }

  Future<SessionData> updateNotes(
      SessionData session, int lotIndex, String notes) async {
    final lot = session.lots[lotIndex] as Map<String, dynamic>;
    lot['notes'] = notes;
    await _writeJson(session);
    return session;
  }

  /// Generates a timestamp-based filename guaranteed unique across devices.
  String nextImageFilename(String deviceId) {
    final n = DateTime.now();
    final ts =
        '${n.year}${_p(n.month)}${_p(n.day)}_${_p(n.hour)}${_p(n.minute)}${_p(n.second)}_${n.millisecond.toString().padLeft(3, '0')}';
    return '${deviceId}_$ts.jpg';
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  Future<void> _writeJson(SessionData session) async {
    final file = File('${session.folderPath}/session.json');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(session.json),
      flush: true,
    );
  }

  String _slugify(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  String _timestamp() {
    final n = DateTime.now();
    return '${n.year}${_p(n.month)}${_p(n.day)}_${_p(n.hour)}${_p(n.minute)}${_p(n.second)}';
  }

  String _p(int v) => v.toString().padLeft(2, '0');
}

// ─── Data classes ─────────────────────────────────────────────────────────────

class SessionData {
  final String folderPath;
  final Map<String, dynamic> json;

  SessionData({required this.folderPath, required this.json});

  List<dynamic> get lots => json['lots'] as List;
  String get name => json['name'] as String? ?? '';
  String get device => json['device'] as String? ?? '';

  Map<String, dynamic>? get currentLot =>
      lots.isNotEmpty ? lots.last as Map<String, dynamic> : null;

  int get currentLotIndex => lots.length - 1;
}

class AuctionFolder {
  final String path;
  final String name;
  final String displayName;

  AuctionFolder(
      {required this.path, required this.name, this.displayName = ''});
}

class SessionFolder {
  final String path;
  final String name;
  final String displayName;
  final int photoCount;

  SessionFolder({
    required this.path,
    required this.name,
    this.displayName = '',
    this.photoCount = 0,
  });
}
