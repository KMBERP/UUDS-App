import 'dart:io';
import 'package:flutter/material.dart';
import '../db/db_helper.dart';
import '../models/models.dart';
import '../utils/page_transitions.dart';
import '../utils/theme.dart';
import '../widgets/app_bottom_nav.dart';
import 'photo_viewer_screen.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  List<InspectionPhoto> _photos = [];
  bool _loading = true;
  String _search = '';

  String _formatTimestamp(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final dd = dt.day.toString().padLeft(2, '0');
      final mm = dt.month.toString().padLeft(2, '0');
      final yy = dt.year.toString();
      final hour24 = dt.hour;
      final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
      final min = dt.minute.toString().padLeft(2, '0');
      final ampm = hour24 >= 12 ? 'PM' : 'AM';
      return '$dd/$mm/$yy  $hour12:$min $ampm';
    } catch (_) {
      return '';
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final photos = await DBHelper.instance.getPhotos();
    setState(() {
      _photos = photos;
      _loading = false;
    });
  }

  Future<void> _deletePhoto(InspectionPhoto p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete photo?'),
        content: const Text('This will remove the photo record. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await DBHelper.instance.deletePhoto(p.id!);
      try {
        final f = File(p.filePath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
      _load();
    }
  }

  // aircraftReg -> inspectionType -> partLocation -> photos
  Map<String, Map<String, Map<String, List<InspectionPhoto>>>> _buildTree() {
    final tree = <String, Map<String, Map<String, List<InspectionPhoto>>>>{};
    final query = _search.trim().toLowerCase();
    for (final p in _photos) {
      if (query.isNotEmpty &&
          !p.aircraftReg.toLowerCase().contains(query) &&
          !p.partLocation.toLowerCase().contains(query)) {
        continue;
      }
      tree.putIfAbsent(p.aircraftReg, () => {});
      tree[p.aircraftReg]!.putIfAbsent(p.inspectionType, () => {});
      tree[p.aircraftReg]![p.inspectionType]!.putIfAbsent(p.partLocation, () => []);
      tree[p.aircraftReg]![p.inspectionType]![p.partLocation]!.add(p);
    }
    return tree;
  }

  @override
  Widget build(BuildContext context) {
    final tree = _buildTree();
    final aircraftKeys = tree.keys.toList()..sort();

    return Scaffold(
      appBar: AppBar(title: const Text('Photo Gallery')),
      bottomNavigationBar: const AppBottomNav(current: AppTab.gallery),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Search aircraft or location...',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : aircraftKeys.isEmpty
                      ? const Center(child: Text('No photos found.', style: TextStyle(color: Colors.black54, fontSize: 16)))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                          itemCount: aircraftKeys.length,
                          itemBuilder: (ctx, i) {
                            final aircraftReg = aircraftKeys[i];
                            final types = tree[aircraftReg]!;
                            final totalCount = types.values
                                .expand((locMap) => locMap.values)
                                .fold<int>(0, (sum, list) => sum + list.length);
                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              elevation: 2,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: ExpansionTile(
                                leading: CircleAvatar(backgroundColor: kPrimary.withOpacity(0.1), child: Icon(Icons.flight, color: kPrimary)),
                                title: Text(aircraftReg, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                subtitle: Text('$totalCount photo(s)'),
                                children: types.entries.map((typeEntry) {
                                  final typeLabel = typeEntry.key;
                                  final locMap = typeEntry.value;
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 6),
                                          child: Text(
                                            typeLabel,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: typeLabel == 'Receiving' ? kPrimary : kDispatch,
                                            ),
                                          ),
                                        ),
                                        ...locMap.entries.map((locEntry) {
                                          final locName = locEntry.key;
                                          final photos = locEntry.value;
                                          return ExpansionTile(
                                            tilePadding: EdgeInsets.zero,
                                            title: Text('$locName  (${photos.length})', style: const TextStyle(fontSize: 14)),
                                            children: [
                                              GridView.builder(
                                                shrinkWrap: true,
                                                physics: const NeverScrollableScrollPhysics(),
                                                padding: const EdgeInsets.only(bottom: 8),
                                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                                  crossAxisCount: 4,
                                                  crossAxisSpacing: 6,
                                                  mainAxisSpacing: 6,
                                                ),
                                                itemCount: photos.length,
                                                itemBuilder: (ctx, gi) {
                                                  final p = photos[gi];
                                                  return GestureDetector(
                                                    onTap: () => Navigator.of(context).push(
                                                      fadeSlideRoute(PhotoViewerScreen(photo: p)),
                                                    ).then((_) => _load()),
                                                    onLongPress: () => _deletePhoto(p),
                                                    child: ClipRRect(
                                                      borderRadius: BorderRadius.circular(6),
                                                      child: Stack(
                                                        fit: StackFit.expand,
                                                        children: [
                                                          File(p.filePath).existsSync()
                                                              ? Image.file(File(p.filePath), fit: BoxFit.cover)
                                                              : Container(color: Colors.grey[300], child: const Icon(Icons.broken_image)),
                                                          Positioned(
                                                            left: 0,
                                                            right: 0,
                                                            bottom: 0,
                                                            child: Container(
                                                              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                                                              decoration: BoxDecoration(
                                                                gradient: LinearGradient(
                                                                  begin: Alignment.topCenter,
                                                                  end: Alignment.bottomCenter,
                                                                  colors: [Colors.black.withOpacity(0.0), Colors.black.withOpacity(0.75)],
                                                                ),
                                                              ),
                                                              child: Text(
                                                                _formatTimestamp(p.timestamp),
                                                                textAlign: TextAlign.center,
                                                                maxLines: 1,
                                                                overflow: TextOverflow.ellipsis,
                                                                style: const TextStyle(color: Colors.white, fontSize: 7.5, fontWeight: FontWeight.w600),
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ),
                                            ],
                                          );
                                        }),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
