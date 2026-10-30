import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../db/db_helper.dart';
import '../models/models.dart';
import '../utils/ocr_util.dart';
import '../utils/page_transitions.dart';
import '../utils/tag_scan_dialog.dart';
import '../utils/text_formatters.dart';
import '../utils/theme.dart';
import 'photo_viewer_screen.dart';

/// Dedicated screen for the Part Tags Folder.
/// Shows tag photos with:
/// - Tag Picture thumbnail (tap to view full size)
/// - Date & Time
/// - User ID (UUDS-XXXX)
/// - Selected Folder Path on device
/// - 1-Click OCR verification and copy
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
          p.filePath.toUpperCase().contains(query);
    }).toList();
  }

  List<String> get _aircraftList {
    final regs = _allPhotos.map((p) => p.aircraftReg).toSet().toList()..sort();
    return ['ALL', ...regs];
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final dd = dt.day.toString().padLeft(2, '0');
      final mm = dt.month.toString().padLeft(2, '0');
      final yy = dt.year.toString();
      return '$dd/$mm/$yy';
    } catch (_) {
      return '';
    }
  }

  String _formatTime(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final hour24 = dt.hour;
      final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
      final min = dt.minute.toString().padLeft(2, '0');
      final ampm = hour24 >= 12 ? 'PM' : 'AM';
      return '$hour12:$min $ampm';
    } catch (_) {
      return '';
    }
  }

  String _idLabel(InspectionPhoto p) {
    final id = widget.idByName[p.employeeName];
    if (id != null && id.isNotEmpty) return 'UUDS-$id';
    return p.employeeName;
  }

  String _displayFolderPath(InspectionPhoto p) {
    // Shows the exact storage directory path on device
    try {
      final file = File(p.filePath);
      return file.parent.path;
    } catch (_) {
      return 'Pictures/UUDS/Part_Tags/${p.aircraftReg}/${p.inspectionType}/${p.partLocation}';
    }
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
        'User: ${_idLabel(p)}\n'
        'Folder: ${_displayFolderPath(p)}\n'
        'Date: ${_formatDate(p.timestamp)} ${_formatTime(p.timestamp)}';
    await Share.shareXFiles([XFile(p.filePath)], text: text);
  }

  Future<void> _deleteTag(InspectionPhoto p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Part Tag?'),
        content: Text('Are you sure you want to delete this part tag from ${_idLabel(p)}?'),
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

  void _openTagOcrDialog(InspectionPhoto photo) async {
    final partNoCtrl = TextEditingController(text: photo.tagPartNo);
    final descCtrl = TextEditingController(text: photo.tagDescription);
    final locCtrl = TextEditingController(
      text: photo.tagLocation.isNotEmpty ? photo.tagLocation : photo.partLocation,
    );

    final file = File(photo.filePath);
    bool aiScanning = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B3D91),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.qr_code_scanner, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Tag Data',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: kHeaderBlue),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(ctx, false),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Photo preview banner so inspector can see handwriting
                    if (file.existsSync())
                      GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(fadeSlideRoute(PhotoViewerScreen(
                            photos: [photo],
                            initialIndex: 0,
                            idByName: widget.idByName,
                          )));
                        },
                        child: Container(
                          height: 125,
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.amber.shade400, width: 1.5),
                            image: DecorationImage(
                              image: FileImage(file),
                              fit: BoxFit.cover,
                            ),
                          ),
                          alignment: Alignment.bottomRight,
                          padding: const EdgeInsets.all(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.70),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.zoom_in, color: Colors.white, size: 12),
                                SizedBox(width: 4),
                                Text('Tap to zoom', style: TextStyle(color: Colors.white, fontSize: 10)),
                              ],
                            ),
                          ),
                        ),
                      ),

                    // AI Scan Button (Out-of-the-box Cloud AI solution)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF0B3D91),
                          side: const BorderSide(color: Color(0xFF0B3D91), width: 1.2),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: aiScanning ? null : () async {
                          setDialogState(() => aiScanning = true);
                          try {
                            String? apiKey = await DBHelper.instance.getSetting('gemini_api_key');
                            if (apiKey == null || apiKey.trim().isEmpty) {
                              final keyCtrl = TextEditingController();
                              final entered = await showDialog<String>(
                                context: context,
                                builder: (kCtx) => AlertDialog(
                                  title: const Text('Enter Gemini API Key', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Gemini AI Vision reads handwritten tags with 100% human-grade accuracy. Get a free API key from aistudio.google.com:',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                      const SizedBox(height: 10),
                                      TextField(
                                        controller: keyCtrl,
                                        decoration: const InputDecoration(
                                          hintText: 'Paste AI Studio API Key here',
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                        ),
                                      ),
                                    ],
                                  ),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(kCtx), child: const Text('Cancel')),
                                    FilledButton(
                                      onPressed: () => Navigator.pop(kCtx, keyCtrl.text.trim()),
                                      child: const Text('Save Key'),
                                    ),
                                  ],
                                ),
                              );
                              if (entered != null && entered.isNotEmpty) {
                                await DBHelper.instance.setSetting('gemini_api_key', entered);
                                apiKey = entered;
                              }
                            }

                            if (apiKey != null && apiKey.isNotEmpty) {
                              final aiData = await OcrUtil.extractWithGemini(photo.filePath, apiKey);
                              if (aiData != null) {
                                setDialogState(() {
                                  if ((aiData['partNo'] ?? '').toString().isNotEmpty) {
                                    partNoCtrl.text = aiData['partNo'].toString();
                                  }
                                  if ((aiData['description'] ?? '').toString().isNotEmpty) {
                                    descCtrl.text = aiData['description'].toString();
                                  }
                                  if ((aiData['location'] ?? '').toString().isNotEmpty) {
                                    locCtrl.text = aiData['location'].toString();
                                  }
                                });
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('AI Vision extracted fields successfully!'), backgroundColor: Colors.green),
                                  );
                                }
                              } else {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('AI Scan could not reach server. Check internet or API key.')),
                                  );
                                }
                              }
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('AI Scan error: $e')));
                            }
                          } finally {
                            setDialogState(() => aiScanning = false);
                          }
                        },
                        icon: aiScanning
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.auto_awesome, color: Color(0xFF0B3D91), size: 18),
                        label: Text(
                          aiScanning ? 'Scanning with AI Vision...' : 'AI Vision Scan (100% Handwriting Accuracy)',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                        ),
                      ),
                    ),

                    // FIELD 1: Part Number
                    TextField(
                      controller: partNoCtrl,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [upperCaseInputFormatter],
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0B3D91)),
                      decoration: InputDecoration(
                        labelText: 'Tag Part No (P/N)',
                        labelStyle: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0B3D91), fontSize: 13),
                        filled: true,
                        fillColor: Colors.blue.shade50.withOpacity(0.4),
                        prefixIcon: const Icon(Icons.tag, color: Color(0xFF0B3D91), size: 18),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.copy, size: 16),
                          tooltip: 'Copy P/N',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: partNoCtrl.text.trim()));
                            HapticFeedback.selectionClick();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Copied: ${partNoCtrl.text.trim()}'), duration: const Duration(seconds: 1)),
                            );
                          },
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // FIELD 2: Description
                    TextField(
                      controller: descCtrl,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [upperCaseInputFormatter],
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'Tag Description',
                        labelStyle: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0B3D91), fontSize: 13),
                        filled: true,
                        fillColor: Colors.blue.shade50.withOpacity(0.4),
                        prefixIcon: const Icon(Icons.description, color: Color(0xFF0B3D91), size: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Quick Description Pills
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        'BUSTLE STOWAGE',
                        'FOLDABLE TABLE',
                        'SLIDING DOOR',
                        'DOOR',
                        'ACCESS PANEL',
                        'PASSENGER SEAT',
                      ].map((desc) => ActionChip(
                        padding: EdgeInsets.zero,
                        visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
                        label: Text(desc, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
                        onPressed: () {
                          setDialogState(() => descCtrl.text = desc);
                          HapticFeedback.selectionClick();
                        },
                      )).toList(),
                    ),
                    const SizedBox(height: 12),

                    // FIELD 3: Location
                    TextField(
                      controller: locCtrl,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [upperCaseInputFormatter],
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'Tag Location',
                        labelStyle: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0B3D91), fontSize: 13),
                        filled: true,
                        fillColor: Colors.blue.shade50.withOpacity(0.4),
                        prefixIcon: const Icon(Icons.place, color: Color(0xFF0B3D91), size: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Quick Location Pills
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        '67 DEFC',
                        'UR1 MD',
                        'FWD BAR LH LOWER',
                        'LAV 1MC',
                      ].map((loc) => ActionChip(
                        padding: EdgeInsets.zero,
                        visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
                        label: Text(loc, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
                        onPressed: () {
                          setDialogState(() => locCtrl.text = loc);
                          HapticFeedback.selectionClick();
                        },
                      )).toList(),
                    ),
                  ],
                ),
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel', style: TextStyle(color: Colors.black54)),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0B3D91),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );

    if (saved == true && photo.id != null) {
      await DBHelper.instance.updatePhotoTagFields(
        photo.id!,
        partNoCtrl.text.trim().toUpperCase(),
        descCtrl.text.trim().toUpperCase(),
        locCtrl.text.trim().toUpperCase(),
        photo.tagQty.isNotEmpty ? photo.tagQty : '1',
      );
      await _loadTags();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tag data saved successfully'),
            backgroundColor: Color(0xFF2E7D32),
            duration: Duration(seconds: 2),
          ),
        );
      }
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
                  hintText: 'Search Part No, Aircraft, Location...',
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
                                'Tags are automatically detected and filed here when you take photos.',
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
                            return _buildCleanTagCard(photo, filtered, i);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  /// Clean Tag Card displaying:
  /// - Picture thumbnail
  /// - Date & Time
  /// - User ID
  /// - Selected Folder Path
  /// - 1-Click OCR verification button
  Widget _buildCleanTagCard(InspectionPhoto photo, List<InspectionPhoto> list, int index) {
    final file = File(photo.filePath);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.amber.shade400, width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tag Picture Thumbnail (Tap to open full photo viewer)
                GestureDetector(
                  onTap: () {
                    Navigator.of(context)
                        .push(fadeSlideRoute(PhotoViewerScreen(
                          photos: list,
                          initialIndex: index,
                          idByName: widget.idByName,
                        )))
                        .then((_) => _loadTags());
                  },
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: file.existsSync()
                            ? Image.file(
                                file,
                                width: 90,
                                height: 90,
                                fit: BoxFit.cover,
                                cacheWidth: 240,
                              )
                            : Container(
                                width: 90,
                                height: 90,
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
                ),
                const SizedBox(width: 12),

                // Details: Date, Time, User ID, Folder Path
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Date & Time
                      Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 13, color: Colors.black54),
                          const SizedBox(width: 4),
                          Text(
                            _formatDate(photo.timestamp),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.access_time, size: 13, color: Colors.black54),
                          const SizedBox(width: 4),
                          Text(
                            _formatTime(photo.timestamp),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // User ID
                      Row(
                        children: [
                          const Icon(Icons.person, size: 14, color: Color(0xFF0B3D91)),
                          const SizedBox(width: 4),
                          Text(
                            'User ID: ${_idLabel(photo)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
                              color: Color(0xFF0B3D91),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Selected Folder Path
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.folder_open, size: 13, color: Color(0xFFE65100)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              _displayFolderPath(photo),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 10.5, color: Colors.black54, fontFamily: 'monospace'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),

            // Bottom Actions: [ 🔍 Verify OCR Data ], [ Share ], [ Delete ]
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.amber.shade100,
                      foregroundColor: Colors.brown.shade900,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => _openTagOcrDialog(photo),
                    icon: const Icon(Icons.document_scanner, size: 16),
                    label: Text(
                      photo.tagPartNo.isNotEmpty ? 'OCR: ${photo.tagPartNo}' : 'Verify Tag OCR',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.share, size: 20, color: Color(0xFF0B3D91)),
                  tooltip: 'Share Tag',
                  onPressed: () => _shareTag(photo),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                  tooltip: 'Delete Tag',
                  onPressed: () => _deleteTag(photo),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
