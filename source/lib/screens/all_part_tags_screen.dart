import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../db/db_helper.dart';
import '../models/models.dart';
import '../utils/page_transitions.dart';
import '../utils/tag_scan_dialog.dart';
import '../utils/text_formatters.dart';
import '../utils/theme.dart';
import 'photo_viewer_screen.dart';

/// Dedicated screen for the Part Tags Repository / Folder.
/// Displays all part tags across all aircraft, with search by Part Number,
/// Description, Location, and Aircraft, plus 1-tap OCR re-scanning and sharing.
class AllPartTagsScreen extends StatefulWidget {
  final Map<String, String> idByName;

  const AllPartTagsScreen({super.key, required this.idByName});

  @override
  State<AllPartTagsScreen> createState() => _AllPartTagsScreenState();
}

class _AllPartTagsScreenState extends State<AllPartTagsScreen> {
  List<InspectionPhoto> _allPhotos = [];
  bool _loading = true;
  String _search = '';
  String _selectedAircraft = 'ALL';

  @override
  void initState() {
    super.initState();
    _loadTags();
  }

  Future<void> _loadTags() async {
    final photos = await DBHelper.instance.getPhotos();
    setState(() {
      _allPhotos = photos.where((p) => p.isTag == 1 || p.tagPartNo.isNotEmpty).toList();
      _loading = false;
    });
  }

  List<InspectionPhoto> get _filteredTags {
    final query = _search.trim().toUpperCase();
    return _allPhotos.where((p) {
      if (_selectedAircraft != 'ALL' && p.aircraftReg != _selectedAircraft) {
        return false;
      }
      if (query.isEmpty) return true;
      return p.tagPartNo.toUpperCase().contains(query) ||
          p.tagDescription.toUpperCase().contains(query) ||
          p.tagLocation.toUpperCase().contains(query) ||
          p.partLocation.toUpperCase().contains(query) ||
          p.aircraftReg.toUpperCase().contains(query) ||
          p.remarks.toUpperCase().contains(query);
    }).toList();
  }

  List<String> get _aircraftList {
    final regs = _allPhotos.map((p) => p.aircraftReg).toSet().toList()..sort();
    return ['ALL', ...regs];
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
      return '$dd/$mm/$yy $hour12:$min $ampm';
    } catch (_) {
      return '';
    }
  }

  String _idLabel(InspectionPhoto p) {
    final id = widget.idByName[p.employeeName];
    if (id != null && id.isNotEmpty) return 'UUDS-$id';
    return p.employeeName;
  }

  Future<void> _shareTag(InspectionPhoto p) async {
    final file = File(p.filePath);
    if (!await file.exists()) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Photo file not found on disk')));
      return;
    }
    final text = 'Part Tag: ${p.tagPartNo.isNotEmpty ? p.tagPartNo : "N/A"}\n'
        'Description: ${p.tagDescription.isNotEmpty ? p.tagDescription : "N/A"}\n'
        'Location: ${p.tagLocation.isNotEmpty ? p.tagLocation : p.partLocation}\n'
        'Aircraft: ${p.aircraftReg}\n'
        'Qty: ${p.tagQty.isNotEmpty ? p.tagQty : "1"}\n'
        'Date: ${_formatTimestamp(p.timestamp)}';
    await Share.shareXFiles([XFile(p.filePath)], text: text);
  }

  Future<void> _deleteTag(InspectionPhoto p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Part Tag Photo?'),
        content: Text('Are you sure you want to delete this part tag (${p.tagPartNo.isNotEmpty ? p.tagPartNo : "tag"})?'),
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
    if (confirm == true && p.id != null) {
      await DBHelper.instance.deletePhoto(p.id!);
      try {
        final f = File(p.filePath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
      await _loadTags();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredTags;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.qr_code_scanner, color: Colors.white, size: 22),
            const SizedBox(width: 8),
            const Text('Part Tags Folder', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFE65100),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_allPhotos.length}',
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Search Bar
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
              color: Colors.white,
              child: TextField(
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [upperCaseInputFormatter],
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF0B3D91)),
                  hintText: 'Search Part No, Desc, Location, Aircraft...',
                  hintStyle: const TextStyle(fontSize: 13),
                  filled: true,
                  fillColor: const Color(0xFFF0F4F8),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),

            // Aircraft Filter Pills
            if (_aircraftList.length > 2)
              Container(
                height: 44,
                color: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _aircraftList.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (ctx, i) {
                    final ac = _aircraftList[i];
                    final isSelected = _selectedAircraft == ac;
                    return ChoiceChip(
                      label: Text(ac),
                      selected: isSelected,
                      selectedColor: const Color(0xFF0B3D91),
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : Colors.black87,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 12,
                      ),
                      onSelected: (_) => setState(() => _selectedAircraft = ac),
                    );
                  },
                ),
              ),

            const Divider(height: 1),

            // Tag List
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.inventory_2_outlined, size: 56, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              Text(
                                _allPhotos.isEmpty
                                    ? 'No part tags recorded yet.'
                                    : 'No matching part tags found.',
                                style: const TextStyle(color: Colors.black54, fontSize: 15, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Use the orange [TAG] button in the Camera to snap airline tags.',
                                style: TextStyle(color: Colors.black45, fontSize: 12),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
                          itemCount: filtered.length,
                          itemBuilder: (ctx, i) {
                            final photo = filtered[i];
                            return _buildTagCard(photo, filtered, i);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTagCard(InspectionPhoto photo, List<InspectionPhoto> list, int index) {
    final hasPartNo = photo.tagPartNo.trim().isNotEmpty;
    final file = File(photo.filePath);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: hasPartNo ? Colors.amber.shade400 : Colors.grey.shade300, width: 1.2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.of(context)
              .push(fadeSlideRoute(PhotoViewerScreen(
                photos: list,
                initialIndex: index,
                idByName: widget.idByName,
              )))
              .then((_) => _loadTags());
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Photo Thumbnail with TAG badge
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: file.existsSync()
                        ? Image.file(
                            file,
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                            cacheWidth: 200,
                          )
                        : Container(
                            width: 80,
                            height: 80,
                            color: Colors.grey.shade300,
                            child: const Icon(Icons.broken_image, color: Colors.grey),
                          ),
                  ),
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE65100),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'TAG',
                        style: TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),

              // Metadata Column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Aircraft Reg & Qty Badges
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0B3D91).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            photo.aircraftReg,
                            style: const TextStyle(
                              color: Color(0xFF0B3D91),
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            photo.inspectionType,
                            style: const TextStyle(color: Colors.black87, fontSize: 10.5, fontWeight: FontWeight.w600),
                          ),
                        ),
                        const Spacer(),
                        if (photo.tagQty.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade100,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.amber.shade400),
                            ),
                            child: Text(
                              'QTY: ${photo.tagQty}',
                              style: TextStyle(color: Colors.amber.shade900, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Part Number
                    Text(
                      hasPartNo ? photo.tagPartNo : 'PART NO NOT SCANNED',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        color: hasPartNo ? const Color(0xFF0B3D91) : Colors.red.shade700,
                        letterSpacing: 0.5,
                      ),
                    ),

                    // Description
                    if (photo.tagDescription.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          photo.tagDescription,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w600),
                        ),
                      ),

                    const SizedBox(height: 4),

                    // Location on Tag / Part Location
                    Row(
                      children: [
                        const Icon(Icons.place, size: 13, color: Colors.black45),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            photo.tagLocation.isNotEmpty
                                ? 'Tag Loc: ${photo.tagLocation}'
                                : 'Loc: ${photo.partLocation}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, color: Colors.black54),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 4),

                    // Timestamp & Inspector
                    Row(
                      children: [
                        Text(
                          _formatTimestamp(photo.timestamp),
                          style: const TextStyle(fontSize: 10, color: Colors.black45),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '· ${_idLabel(photo)}',
                          style: const TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // Action buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            minimumSize: const Size(0, 30),
                            side: BorderSide(color: Colors.amber.shade700),
                          ),
                          onPressed: () async {
                            final updated = await showTagScanDialog(context, photo);
                            if (updated) _loadTags();
                          },
                          icon: Icon(Icons.qr_code_scanner, size: 14, color: Colors.amber.shade900),
                          label: Text(
                            hasPartNo ? 'Edit OCR' : 'Scan OCR',
                            style: TextStyle(fontSize: 11, color: Colors.amber.shade900, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          icon: const Icon(Icons.share, size: 18, color: Color(0xFF0B3D91)),
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Share Tag',
                          onPressed: () => _shareTag(photo),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Delete Tag',
                          onPressed: () => _deleteTag(photo),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
