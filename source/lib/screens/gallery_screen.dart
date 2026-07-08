import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../db/db_helper.dart';
import '../models/models.dart';
import '../utils/backup_util.dart';
import '../utils/page_transitions.dart';
import '../utils/storage_paths.dart';
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
  List<Employee> _employees = [];
  bool _loading = true;
  bool _backingUp = false;
  String _search = '';
  String _storagePathLabel = '';

  // Multi-select mode, so 2+ photos can be shared together at once.
  bool _selectMode = false;
  final Set<int> _selectedIds = {};

  Map<String, String> get _idByName => {for (final e in _employees) e.name: e.idNumber};

  String _idLabel(InspectionPhoto p) {
    final id = _idByName[p.employeeName];
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

  @override
  void initState() {
    super.initState();
    _load();
    _loadStoragePath();
  }

  Future<void> _loadStoragePath() async {
    final root = await StoragePaths.root();
    if (mounted) {
      setState(() => _storagePathLabel = root.path);
    }
  }

  Future<void> _load() async {
    final photos = await DBHelper.instance.getPhotos();
    final employees = await DBHelper.instance.getEmployees();
    setState(() {
      _photos = photos;
      _employees = employees;
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

  Future<void> _backup() async {
    final selection = await _showBackupSelectionDialog();
    if (selection == null) return;
    setState(() => _backingUp = true);
    try {
      final path = await BackupUtil.createSelectiveBackupAndShare(selection['aircraft']!, selection['locations']!);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Backup saved: $path')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Backup failed: $e')));
    } finally {
      if (mounted) setState(() => _backingUp = false);
    }
  }

  Future<Map<String, Set<String>>?> _showBackupSelectionDialog() async {
    final aircraftList = await DBHelper.instance.getAircraft();
    final locationList = await DBHelper.instance.getPartLocations();
    Set<String> selectedAircraft = aircraftList.map((a) => a.regNo).toSet();
    Set<String> selectedLocations = locationList.map((l) => l.name).toSet();

    if (!mounted) return null;
    return showDialog<Map<String, Set<String>>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Select Backup Scope'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Aircraft', style: TextStyle(fontWeight: FontWeight.bold)),
                      TextButton(
                        onPressed: () => setDialogState(() {
                          selectedAircraft =
                              selectedAircraft.length == aircraftList.length ? {} : aircraftList.map((a) => a.regNo).toSet();
                        }),
                        child: const Text('Toggle All'),
                      ),
                    ],
                  ),
                  ...aircraftList.map((a) => CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(a.regNo),
                        value: selectedAircraft.contains(a.regNo),
                        onChanged: (v) => setDialogState(() {
                          if (v == true) {
                            selectedAircraft.add(a.regNo);
                          } else {
                            selectedAircraft.remove(a.regNo);
                          }
                        }),
                      )),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Part Locations', style: TextStyle(fontWeight: FontWeight.bold)),
                      TextButton(
                        onPressed: () => setDialogState(() {
                          selectedLocations =
                              selectedLocations.length == locationList.length ? {} : locationList.map((l) => l.name).toSet();
                        }),
                        child: const Text('Toggle All'),
                      ),
                    ],
                  ),
                  ...locationList.map((l) => CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(l.name),
                        value: selectedLocations.contains(l.name),
                        onChanged: (v) => setDialogState(() {
                          if (v == true) {
                            selectedLocations.add(l.name);
                          } else {
                            selectedLocations.remove(l.name);
                          }
                        }),
                      )),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, {'aircraft': selectedAircraft, 'locations': selectedLocations}),
              child: const Text('Backup'),
            ),
          ],
        ),
      ),
    );
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
      appBar: AppBar(
        title: Text(_selectMode ? '${_selectedIds.length} selected' : 'Photo Gallery'),
        actions: [
          IconButton(
            icon: Icon(_selectMode ? Icons.close_rounded : Icons.checklist_rounded),
            tooltip: _selectMode ? 'Cancel selection' : 'Select photos to share',
            onPressed: _toggleSelectMode,
          ),
          if (!_selectMode)
            _backingUp
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                  )
                : IconButton(
                    icon: const Icon(Icons.backup_rounded),
                    tooltip: 'Backup Data',
                    onPressed: _backup,
                  ),
        ],
      ),
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
                                                  final selected = _selectedIds.contains(p.id);
                                                  return GestureDetector(
                                                    onTap: () {
                                                      if (_selectMode) {
                                                        _toggleSelected(p);
                                                        return;
                                                      }
                                                      Navigator.of(context).push(
                                                        fadeSlideRoute(PhotoViewerScreen(
                                                          photos: photos,
                                                          initialIndex: gi,
                                                          idByName: _idByName,
                                                        )),
                                                      ).then((_) => _load());
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
                                                                  decoration: BoxDecoration(
                                                                    color: Colors.black.withOpacity(0.55),
                                                                    shape: BoxShape.circle,
                                                                  ),
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
                                                                child: selected
                                                                    ? const Icon(Icons.check, color: Colors.white, size: 13)
                                                                    : null,
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
            // Footer: shows where all photos are stored on the device.
            if (_storagePathLabel.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                color: kPrimary.withOpacity(0.06),
                child: Row(
                  children: [
                    Icon(Icons.folder_open, size: 15, color: kPrimary.withOpacity(0.7)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Saved at: $_storagePathLabel  ·  also in Gallery/Photos under Pictures/UUDS',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10.5, color: kPrimary.withOpacity(0.8)),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
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
