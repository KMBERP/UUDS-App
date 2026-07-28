import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../db/db_helper.dart';
import '../models/models.dart';

class PhotoViewerScreen extends StatefulWidget {
  final List<InspectionPhoto> photos;
  final int initialIndex;
  final Map<String, String> idByName;

  const PhotoViewerScreen({
    super.key,
    required this.photos,
    required this.initialIndex,
    this.idByName = const {},
  });

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  late final PageController _pageController;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  InspectionPhoto get _current => widget.photos[_index];

  String _idLabel(InspectionPhoto p) {
    final id = widget.idByName[p.employeeName];
    if (id != null && id.isNotEmpty) return 'UUDS-$id';
    return p.employeeName;
  }

  void _showInfo(BuildContext context) {
    final photo = _current;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Aircraft: ${photo.aircraftReg}', style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('Type: ${photo.inspectionType}'),
            Text('Part Location: ${photo.partLocation}'),
            Text('Inspector: ${photo.employeeName} (${_idLabel(photo)})'),
            Text('Date: ${DateFormat('dd MMM yyyy, HH:mm').format(DateTime.parse(photo.timestamp))}'),
            if (photo.remarks.isNotEmpty) Text('Remarks: ${photo.remarks}'),
            if (photo.tagPartNo.isNotEmpty) Text('Tag Part No.: ${photo.tagPartNo}'),
            if (photo.tagDescription.isNotEmpty) Text('Tag Description: ${photo.tagDescription}'),
            if (photo.tagLocation.isNotEmpty) Text('Tag Location: ${photo.tagLocation}'),
            if (photo.tagQty.isNotEmpty) Text('Tag Qty: ${photo.tagQty}'),
            const SizedBox(height: 6),
            Text('Saved at: ${File(photo.filePath).parent.path}', style: const TextStyle(fontSize: 11, color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  Future<void> _sharePhoto(BuildContext context) async {
    final photo = _current;
    final file = File(photo.filePath);
    if (!await file.exists()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo file not found on device.')),
        );
      }
      return;
    }
    final caption =
        '${photo.aircraftReg} - ${photo.inspectionType} - ${photo.partLocation}';
    await Share.shareXFiles([XFile(file.path)], text: caption);
  }

  Future<void> _delete(BuildContext context) async {
    final photo = _current;
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
      await DBHelper.instance.deletePhoto(photo.id!);
      try {
        final f = File(photo.filePath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
      if (context.mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          '${_index + 1} / ${widget.photos.length}',
          style: const TextStyle(fontSize: 14, color: Colors.white70),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share this photo',
            onPressed: () => _sharePhoto(context),
          ),
          IconButton(icon: const Icon(Icons.info_outline), onPressed: () => _showInfo(context)),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(context)),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: widget.photos.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (ctx, i) {
                  final p = widget.photos[i];
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      Center(
                        child: InteractiveViewer(
                          minScale: 0.5,
                          maxScale: 5,
                          child: Image.file(File(p.filePath)),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.black.withOpacity(0.65), Colors.black.withOpacity(0.0)],
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_idLabel(p), style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
                              Text(
                                DateFormat('dd/MM/yyyy  h:mm a').format(DateTime.parse(p.timestamp).toLocal()),
                                style: const TextStyle(color: Colors.white, fontSize: 12.5),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [Colors.black.withOpacity(0.7), Colors.black.withOpacity(0.0)],
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  'A/C: ${p.aircraftReg}',
                                  style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Location: ${p.partLocation}',
                                  style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.right,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            // Footer: on-device folder location where this photo is saved.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: const Color(0xFF111111),
              child: Row(
                children: [
                  const Icon(Icons.folder_open, color: Colors.white38, size: 15),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      File(_current.filePath).parent.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white54, fontSize: 10.5),
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
