import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../db/db_helper.dart';
import '../models/models.dart';
import '../utils/page_transitions.dart';
import '../utils/tag_scan_dialog.dart';
import '../utils/theme.dart';
import '../widgets/app_bottom_nav.dart';
import 'photo_viewer_screen.dart';

/// Shown after picking an aircraft in the Gallery tab. Splits that
/// aircraft's photos into two tabs - Receiving and Dispatch - each grouped
/// by part location, same grid/photo-viewer/share/delete behaviour as
/// before.
class AircraftGalleryScreen extends StatefulWidget {
  final String aircraftReg;
  final List<InspectionPhoto> photos;
  final Map<String, String> idByName;

  const AircraftGalleryScreen({
    super.key,
    required this.aircraftReg,
    required this.photos,
    required this.idByName,
  });

  @override
  State<AircraftGalleryScreen> createState() => _AircraftGalleryScreenState();
}

class _AircraftGalleryScreenState extends State<AircraftGalleryScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late List<InspectionPhoto> _photos = widget.photos;
  bool _selectMode = false;
  final Set<int> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // Rebuilds the custom tab header as the selection/swipe animates, so
    // the "3D" raised/sunken look tracks the live TabBarView position.
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _idLabel(InspectionPhoto p) {
    final id = widget.idByName[p.employeeName];
    if (id != null && id.isNotEmpty) return 'UUDS-$id';
    return p.employeeName;
  }

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

  Future<void> _reload() async {
    final all = await DBHelper.instance.getPhotos();
    setState(() {
      _photos = all.where((p) => p.aircraftReg == widget.aircraftReg).toList();
    });
  }

  void _toggleSelectMode() {
    setState(() {
      _selectMode = !_selectMode;
      _selectedIds.clear();
    });
  }

  void _toggleSelected(InspectionPhoto p) {
    if (p.id == null) return;
    setState(() {
      if (_selectedIds.contains(p.id)) {
        _selectedIds.remove(p.id);
      } else {
        _selectedIds.add(p.id!);
      }
    });
  }

  Future<void> _sharePhoto(InspectionPhoto p) async {
    final file = File(p.filePath);
    if (!await file.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo file not found on device.')),
        );
      }
      return;
    }
    final caption = '${p.aircraftReg} - ${p.inspectionType} - ${p.partLocation}';
    await Share.shareXFiles([XFile(file.path)], text: caption);
  }

  Future<void> _scanTag(InspectionPhoto p) async {
    final saved = await showTagScanDialog(context, p);
    if (saved) await _reload();
  }

  Future<void> _shareSelected() async {
    final selectedPhotos = _photos.where((p) => _selectedIds.contains(p.id)).toList();
    final files = <XFile>[];
    for (final p in selectedPhotos) {
      final f = File(p.filePath);
      if (await f.exists()) files.add(XFile(f.path));
    }
    if (files.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('None of the selected photos were found on device.')),
        );
      }
      return;
    }
    await Share.shareXFiles(files, text: 'UUDS Aero DWC - ${files.length} photo(s)');
    if (mounted) {
      setState(() {
        _selectMode = false;
        _selectedIds.clear();
      });
    }
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
      await _reload();
    }
  }

  // partLocation -> photos, for one inspection type.
  Map<String, List<InspectionPhoto>> _locationsFor(String inspectionType) {
    final map = <String, List<InspectionPhoto>>{};
    for (final p in _photos) {
      if (p.inspectionType != inspectionType) continue;
      map.putIfAbsent(p.partLocation, () => []).add(p);
    }
    return map;
  }

  Widget _tabButton({
    required int index,
    required String label,
    required IconData icon,
    required Color color,
    required int count,
  }) {
    final selected = _tabController.index == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => _tabController.animateTo(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          margin: EdgeInsets.symmetric(horizontal: 3, vertical: selected ? 0 : 4),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: selected
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [color.withOpacity(0.95), color],
                  )
                : null,
            color: selected ? null : color.withOpacity(0.10),
            boxShadow: selected
                ? [
                    BoxShadow(color: color.withOpacity(0.40), blurRadius: 8, offset: const Offset(0, 3)),
                    const BoxShadow(color: Colors.white, blurRadius: 0, spreadRadius: -1, offset: Offset(0, -1)),
                  ]
                : [],
            border: selected ? null : Border.all(color: color.withOpacity(0.25)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: selected ? 21 : 18, color: selected ? Colors.white : color),
              const SizedBox(height: 3),
              Text(
                '$label ($count)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? Colors.white : color,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  fontSize: selected ? 11.5 : 10.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeTab(String inspectionType) {
    final locMap = _locationsFor(inspectionType);
    final locNames = locMap.keys.toList()..sort();
    if (locNames.isEmpty) {
      return Center(
        child: Text('No $inspectionType photos yet.', style: const TextStyle(color: Colors.black54, fontSize: 15)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      itemCount: locNames.length,
      itemBuilder: (ctx, i) {
        final locName = locNames[i];
        final photos = locMap[locName]!;
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ExpansionTile(
            title: Text('$locName  (${photos.length})', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            children: [
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                ),
                itemCount: photos.length,
                itemBuilder: (ctx, gi) {
                  final p = photos[gi];
                  final selected = _selectedIds.contains(p.id);
                  return GestureDetector(
                    onTap: () {
                      if (_selectMode) {
                        _toggleSelected(p);
                        return;
                      }
                      Navigator.of(context)
                          .push(fadeSlideRoute(PhotoViewerScreen(
                            photos: photos,
                            initialIndex: gi,
                            idByName: widget.idByName,
                          )))
                          .then((_) => _reload());
                    },
                    onLongPress: () {
                      if (_selectMode) {
                        _toggleSelected(p);
                      } else {
                        _deletePhoto(p);
                      }
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          File(p.filePath).existsSync()
                              // cacheWidth downsamples the *decode*, not
                              // just the display size - this is the actual
                              // fix for the app closing in large folders.
                              // Without it, Flutter decodes every photo at
                              // full camera resolution (several MB each as
                              // a raw bitmap) just to show a small grid
                              // square; with hundreds of photos in one
                              // location, that exhausts memory and Android
                              // kills the app outright. 300px is more than
                              // enough detail for this thumbnail size.
                              ? Image.file(File(p.filePath), fit: BoxFit.cover, cacheWidth: 300)
                              : Container(color: Colors.grey[300], child: const Icon(Icons.broken_image)),
                          Positioned(
                            left: 0,
                            right: 0,
                            top: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                              color: Colors.black.withOpacity(0.55),
                              child: Text(
                                _idLabel(p),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
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
                          if (p.isTag == 1)
                            Positioned(
                              left: 2,
                              bottom: 14,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.amberAccent,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'TAG',
                                  style: TextStyle(color: Colors.black, fontSize: 8, fontWeight: FontWeight.w900),
                                ),
                              ),
                            ),
                          if (!_selectMode)
                            Positioned(
                              right: 2,
                              top: 2,
                              child: GestureDetector(
                                onTap: () => _sharePhoto(p),
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.55), shape: BoxShape.circle),
                                  child: const Icon(Icons.share, color: Colors.white, size: 11),
                                ),
                              ),
                            ),
                          if (!_selectMode)
                            Positioned(
                              left: 2,
                              top: 2,
                              child: GestureDetector(
                                onTap: () => _scanTag(p),
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.55), shape: BoxShape.circle),
                                  child: Icon(
                                    p.tagPartNo.trim().isEmpty ? Icons.document_scanner_outlined : Icons.check_circle,
                                    color: p.tagPartNo.trim().isEmpty ? Colors.white : Colors.lightGreenAccent,
                                    size: 11,
                                  ),
                                ),
                              ),
                            ),
                          if (_selectMode)
                            Positioned(
                              right: 2,
                              top: 2,
                              child: Container(
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: selected ? kPrimary : Colors.black.withOpacity(0.4),
                                  border: Border.all(color: Colors.white, width: 1.5),
                                ),
                                child: selected ? const Icon(Icons.check, color: Colors.white, size: 13) : null,
                              ),
                            ),
                          if (selected)
                            Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: kPrimary, width: 3),
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTagsTab() {
    final tags = _photos.where((p) => p.isTag == 1 || p.tagPartNo.isNotEmpty).toList();
    if (tags.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.qr_code_scanner, size: 52, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                'No part tags recorded for ${widget.aircraftReg}.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54, fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              const Text(
                'Use the orange [TAG] button in the Camera to snap airline tags.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black45, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    // Group tags by location
    final tagLocMap = <String, List<InspectionPhoto>>{};
    for (final t in tags) {
      final loc = t.tagLocation.isNotEmpty ? t.tagLocation : t.partLocation;
      tagLocMap.putIfAbsent(loc, () => []).add(t);
    }
    final locNames = tagLocMap.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      itemCount: locNames.length,
      itemBuilder: (ctx, i) {
        final locName = locNames[i];
        final locTags = tagLocMap[locName]!;
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ExpansionTile(
            initiallyExpanded: true,
            leading: const Icon(Icons.label_important, color: Color(0xFFE65100)),
            title: Text('$locName (${locTags.length})', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            children: locTags.map((p) {
              final file = File(p.filePath);
              final hasPartNo = p.tagPartNo.trim().isNotEmpty;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.black12, width: 0.5)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Thumbnail
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context)
                            .push(fadeSlideRoute(PhotoViewerScreen(
                              photos: tags,
                              initialIndex: tags.indexOf(p),
                              idByName: widget.idByName,
                            )))
                            .then((_) => _reload());
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Stack(
                          children: [
                            file.existsSync()
                                ? Image.file(file, width: 68, height: 68, fit: BoxFit.cover, cacheWidth: 200)
                                : Container(width: 68, height: 68, color: Colors.grey.shade300, child: const Icon(Icons.broken_image)),
                            Positioned(
                              top: 2,
                              left: 2,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE65100),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'TAG',
                                  style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Information
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  hasPartNo ? p.tagPartNo : 'PART NO NOT SCANNED',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13.5,
                                    color: hasPartNo ? const Color(0xFF0B3D91) : Colors.red.shade700,
                                  ),
                                ),
                              ),
                              if (p.tagQty.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.amber.shade300),
                                  ),
                                  child: Text('QTY: ${p.tagQty}', style: TextStyle(fontSize: 9.5, color: Colors.amber.shade900, fontWeight: FontWeight.bold)),
                                ),
                            ],
                          ),
                          if (p.tagDescription.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                p.tagDescription,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11.5, color: Colors.black87, fontWeight: FontWeight.w600),
                              ),
                            ),
                          const SizedBox(height: 3),
                          Text(
                            '${_formatTimestamp(p.timestamp)} · ${_idLabel(p)}',
                            style: const TextStyle(fontSize: 10, color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                    // Action Buttons
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.qr_code_scanner, size: 20, color: Color(0xFFE65100)),
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Scan / Edit Tag OCR',
                          onPressed: () => _scanTag(p),
                        ),
                        IconButton(
                          icon: const Icon(Icons.share, size: 18, color: Color(0xFF0B3D91)),
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Share',
                          onPressed: () => _sharePhoto(p),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectMode ? '${_selectedIds.length} selected' : widget.aircraftReg),
        actions: [
          IconButton(
            icon: Icon(_selectMode ? Icons.close_rounded : Icons.checklist_rounded),
            tooltip: _selectMode ? 'Cancel selection' : 'Select photos to share',
            onPressed: _toggleSelectMode,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            color: Colors.white,
            child: Row(
              children: [
                _tabButton(
                  index: 0,
                  label: 'Receiving',
                  icon: Icons.flight_land_rounded,
                  color: kPrimary,
                  count: _locationsFor('Receiving').values.fold<int>(0, (s, l) => s + l.length),
                ),
                _tabButton(
                  index: 1,
                  label: 'Dispatch',
                  icon: Icons.flight_takeoff_rounded,
                  color: kDispatch,
                  count: _locationsFor('Dispatch').values.fold<int>(0, (s, l) => s + l.length),
                ),
                _tabButton(
                  index: 2,
                  label: 'Part Tags',
                  icon: Icons.qr_code_scanner,
                  color: const Color(0xFFE65100),
                  count: _photos.where((p) => p.isTag == 1 || p.tagPartNo.isNotEmpty).length,
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTypeTab('Receiving'),
                _buildTypeTab('Dispatch'),
                _buildTagsTab(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(current: AppTab.gallery),
      floatingActionButton: (_selectMode && _selectedIds.isNotEmpty)
          ? FloatingActionButton.extended(
              onPressed: _shareSelected,
              backgroundColor: kPrimary,
              icon: const Icon(Icons.share, color: Colors.white),
              label: Text('Share ${_selectedIds.length}', style: const TextStyle(color: Colors.white)),
            )
          : null,
    );
  }
}
