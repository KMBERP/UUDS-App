import 'package:flutter/material.dart';
import '../db/db_helper.dart';
import '../models/models.dart';
import '../utils/backup_util.dart';
import '../utils/build_info.dart';
import '../utils/page_transitions.dart';
import '../utils/storage_paths.dart';
import '../utils/theme.dart';
import '../widgets/app_bottom_nav.dart';
import 'aircraft_gallery_screen.dart';

/// Landing screen for the Gallery tab: pick an aircraft, then it opens into
/// a Receiving/Dispatch tabbed view of just that aircraft's photos (see
/// AircraftGalleryScreen).
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

  Map<String, String> get _idByName => {for (final e in _employees) e.name: e.idNumber};

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

  // aircraftReg -> photos, filtered by the search box (matches reg number).
  Map<String, List<InspectionPhoto>> _buildAircraftMap() {
    final map = <String, List<InspectionPhoto>>{};
    final query = _search.trim().toLowerCase();
    for (final p in _photos) {
      if (query.isNotEmpty && !p.aircraftReg.toLowerCase().contains(query)) continue;
      map.putIfAbsent(p.aircraftReg, () => []).add(p);
    }
    return map;
  }

  Future<void> _openAircraft(String aircraftReg, List<InspectionPhoto> photos) async {
    await Navigator.of(context).push(fadeSlideRoute(AircraftGalleryScreen(
      aircraftReg: aircraftReg,
      photos: photos,
      idByName: _idByName,
    )));
    // Photos may have been deleted/shared while inside - refresh counts.
    _load();
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
    final locationNames = await DBHelper.instance.getAllDistinctPartLocationNames();
    Set<String> selectedAircraft = aircraftList.map((a) => a.regNo).toSet();
    Set<String> selectedLocations = locationNames.toSet();

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
                              selectedLocations.length == locationNames.length ? {} : locationNames.toSet();
                        }),
                        child: const Text('Toggle All'),
                      ),
                    ],
                  ),
                  ...locationNames.map((name) => CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(name),
                        value: selectedLocations.contains(name),
                        onChanged: (v) => setDialogState(() {
                          if (v == true) {
                            selectedLocations.add(name);
                          } else {
                            selectedLocations.remove(name);
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

  @override
  Widget build(BuildContext context) {
    final aircraftMap = _buildAircraftMap();
    final aircraftKeys = aircraftMap.keys.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Photo Gallery'),
        actions: [
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
                  hintText: 'Search aircraft registration...',
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
                            final photos = aircraftMap[aircraftReg]!;
                            final receivingCount = photos.where((p) => p.inspectionType == 'Receiving').length;
                            final dispatchCount = photos.where((p) => p.inspectionType == 'Dispatch').length;
                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              elevation: 2,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                leading: CircleAvatar(backgroundColor: kPrimary.withOpacity(0.1), child: Icon(Icons.flight, color: kPrimary)),
                                title: Text(aircraftReg, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                subtitle: Text(
                                  'Receiving: $receivingCount  ·  Dispatch: $dispatchCount',
                                  style: TextStyle(color: Colors.grey.shade700),
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _openAircraft(aircraftReg, photos),
                              ),
                            );
                          },
                        ),
            ),
            // Footer: shows where all photos are stored on the device, and
            // which build this is (for confirming a fresh CI build is
            // actually installed when troubleshooting the Gallery mirror).
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
                        'Saved at: $_storagePathLabel  ·  also in Gallery/Photos under Pictures/UUDS  ·  Build: $kBuildId',
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
    );
  }
}
