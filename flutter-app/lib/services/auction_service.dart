import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class AuctionService {
  static const String _rootDir = 'lot-builder';

  Future<Directory> get rootDirectory async {
    // Use public Documents folder so files are visible via USB and file managers.
    // Requires MANAGE_EXTERNAL_STORAGE on Android 11+.
    final ext = await getExternalStorageDirectory();
    // getExternalStorageDirectory() returns .../Android/data/<pkg>/files
    // Navigate up 4 levels to reach /storage/emulated/0
    final storageRoot = ext!.parent.parent.parent.parent;
    final dir = Directory('${storageRoot.path}/Documents/$_rootDir');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Must be called before any file operations on Android 11+.
  Future<bool> requestStoragePermission() async {
    if (await Permission.manageExternalStorage.isGranted) return true;
    final status = await Permission.manageExternalStorage.request();
    return status.isGranted;
  }

  Future<List<AuctionFolder>> listAuctions() async {
    final root = await rootDirectory;
    final dirs = root.listSync().whereType<Directory>().toList();
    dirs.sort((a, b) => b.path.compareTo(a.path)); // newest first

    final auctions = <AuctionFolder>[];
    for (final dir in dirs) {
      final jsonFile = File('${dir.path}/auction.json');
      if (await jsonFile.exists()) {
        String displayName = '';
        try {
          final contents = await jsonFile.readAsString();
          final data = jsonDecode(contents) as Map<String, dynamic>;
          displayName =
              (data['auction'] as Map?)?['title'] as String? ?? '';
        } catch (_) {}
        auctions.add(AuctionFolder(
          path: dir.path,
          name: dir.path.split(RegExp(r'[/\\]')).last,
          displayName: displayName,
        ));
      }
    }
    return auctions;
  }

  Future<AuctionData> createAuction({String name = ''}) async {
    final root = await rootDirectory;
    final timestamp = _timestamp();
    final folder = Directory('${root.path}/auction_$timestamp');
    await folder.create();

    final auction = AuctionData(
      folderPath: folder.path,
      json: _emptyAuction(name: name),
    );
    await _writeJson(auction);
    return auction;
  }

  Future<AuctionData> loadAuction(String folderPath) async {
    final jsonFile = File('$folderPath/auction.json');
    final contents = await jsonFile.readAsString();
    return AuctionData(
      folderPath: folderPath,
      json: jsonDecode(contents),
    );
  }

  Future<AuctionData> addLot(AuctionData auction) async {
    final lots = auction.lots;
    final nextNum = lots.length + 1;
    lots.add({
      'id': 'lot_${nextNum.toString().padLeft(3, '0')}',
      'sequence': nextNum,
      'images': [],
      'ai_title': null,
      'ai_description': null,
      'title': null,
      'description': null,
      'notes': '',
      'platform_lot_id': null,
      'status': 'captured',
    });
    await _writeJson(auction);
    return auction;
  }

  Future<AuctionData> addImage(
      AuctionData auction, int lotIndex, String filename) async {
    final lot = auction.lots[lotIndex] as Map<String, dynamic>;
    (lot['images'] as List).add({'filename': filename, 'platform_uuid': null});
    await _writeJson(auction);
    return auction;
  }

  Future<AuctionData> deleteImage(
      AuctionData auction, int lotIndex, int imageIndex) async {
    final lot = auction.lots[lotIndex] as Map<String, dynamic>;
    final images = lot['images'] as List;
    final filename = (images[imageIndex] as Map)['filename'] as String;
    final file = File('${auction.folderPath}/$filename');
    if (await file.exists()) await file.delete();
    images.removeAt(imageIndex);
    await _writeJson(auction);
    return auction;
  }

  Future<AuctionData> removeLot(AuctionData auction, int lotIndex) async {
    auction.lots.removeAt(lotIndex);
    _renumberLots(auction);
    await _writeJson(auction);
    return auction;
  }

  Future<AuctionData> insertLot(AuctionData auction, int afterLotIndex) async {
    auction.lots.insert(afterLotIndex + 1, {
      'id': '',
      'sequence': 0,
      'images': [],
      'ai_title': null,
      'ai_description': null,
      'title': null,
      'description': null,
      'notes': '',
      'platform_lot_id': null,
      'status': 'captured',
    });
    _renumberLots(auction);
    await _writeJson(auction);
    return auction;
  }

  /// Removes the last lot if it has no images. Call before showing lot preview.
  Future<AuctionData> cleanEmptyLastLot(AuctionData auction) async {
    if (auction.lots.isEmpty) return auction;
    final last = auction.lots.last as Map<String, dynamic>;
    if ((last['images'] as List).isEmpty) {
      auction.lots.removeLast();
      await _writeJson(auction);
    }
    return auction;
  }

  Future<AuctionData> splitLot(
      AuctionData auction, int lotIndex, int splitAtIndex) async {
    final lot = auction.lots[lotIndex] as Map<String, dynamic>;
    final images = (lot['images'] as List).cast<Map<String, dynamic>>();

    final keepImages = images.sublist(0, splitAtIndex);
    final moveImages = images.sublist(splitAtIndex);

    lot['images'] = keepImages;

    auction.lots.insert(lotIndex + 1, {
      'id': '',
      'sequence': 0,
      'images': moveImages,
      'ai_title': null,
      'ai_description': null,
      'title': null,
      'description': null,
      'notes': '',
      'platform_lot_id': null,
      'status': 'captured',
    });

    _renumberLots(auction);
    await _writeJson(auction);
    return auction;
  }

  Future<AuctionData> updateNotes(
      AuctionData auction, int lotIndex, String notes) async {
    final lot = auction.lots[lotIndex] as Map<String, dynamic>;
    lot['notes'] = notes;
    await _writeJson(auction);
    return auction;
  }

  void _renumberLots(AuctionData auction) {
    for (int i = 0; i < auction.lots.length; i++) {
      final lot = auction.lots[i] as Map<String, dynamic>;
      lot['sequence'] = i + 1;
      lot['id'] = 'lot_${(i + 1).toString().padLeft(3, '0')}';
    }
  }

  String nextImageFilename(AuctionData auction) {
    final total =
        auction.lots.fold<int>(0, (sum, l) => sum + ((l['images'] as List).length));
    return 'img_${(total + 1).toString().padLeft(3, '0')}.jpg';
  }

  Future<void> _writeJson(AuctionData auction) async {
    final file = File('${auction.folderPath}/auction.json');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(auction.json),
      flush: true,
    );
  }

  String _timestamp() {
    final n = DateTime.now();
    return '${n.year}${_p(n.month)}${_p(n.day)}_${_p(n.hour)}${_p(n.minute)}${_p(n.second)}';
  }

  String _p(int v) => v.toString().padLeft(2, '0');

  Map<String, dynamic> _emptyAuction({String name = ''}) => {
        'version': '1.0',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'auction': {
          'title': name,
          'description': '',
          'platform_id': null,
        },
        'lots': [],
      };
}

class AuctionData {
  final String folderPath;
  final Map<String, dynamic> json;

  AuctionData({required this.folderPath, required this.json});

  List<dynamic> get lots => json['lots'] as List;

  String get name => (json['auction'] as Map)['title'] as String? ?? '';

  Map<String, dynamic>? get currentLot =>
      lots.isNotEmpty ? lots.last as Map<String, dynamic> : null;

  int get currentLotIndex => lots.length - 1;

  int get currentLotPhotoCount =>
      currentLot == null ? 0 : (currentLot!['images'] as List).length;
}

class AuctionFolder {
  final String path;
  final String name;
  final String displayName;

  AuctionFolder({required this.path, required this.name, this.displayName = ''});
}
