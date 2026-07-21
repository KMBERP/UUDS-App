import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../db/db_helper.dart';
import '../models/models.dart';
import '../utils/page_transitions.dart';
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
    _tabController = TabController(length: 2, vsync: this);
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
          margin: EdgeInsets.symmetric(horizontal: 6, vertical: selected ? 0 : 6),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
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
                    BoxShadow(color: color.withOpacity(0.45), blurRadius: 12, offset: const Offset(0, 5)),
                    const BoxShadow(color: Colors.white, blurRadius: 0, spreadRadius: -1, offset: Offset(0, -1)),
                  ]
                : [],
            border: selected ? null : Border.all(color: color.withOpacity(0.25)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: selected ? 24 : 20, color: selected ? Colors.white : color),
              const SizedBox(height: 4),
              Text(
                '$label ($count)',
                style: TextStyle(
                  color: selected ? Colors.white : color,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  fontSize: selected ? 14 : 13,
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
                              ? Image.file(File(p.filePath), fit: BoxFit.cover)
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
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
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
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTypeTab('Receiving'),
                _buildTypeTab('Dispatch'),
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
