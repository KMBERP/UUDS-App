import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../db/db_helper.dart';
import '../models/models.dart';

class PhotoViewerScreen extends StatelessWidget {
  final InspectionPhoto photo;
  const PhotoViewerScreen({super.key, required this.photo});

  void _showInfo(BuildContext context) {
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
            Text('Inspector: ${photo.employeeName}'),
            Text('Date: ${DateFormat('dd MMM yyyy, HH:mm').format(DateTime.parse(photo.timestamp))}'),
            if (photo.remarks.isNotEmpty) Text('Remarks: ${photo.remarks}'),
            if (photo.tagPartNo.isNotEmpty) Text('Tag Part No.: ${photo.tagPartNo}'),
            if (photo.tagDescription.isNotEmpty) Text('Tag Description: ${photo.tagDescription}'),
            if (photo.tagLocation.isNotEmpty) Text('Tag Location: ${photo.tagLocation}'),
            if (photo.tagQty.isNotEmpty) Text('Tag Qty: ${photo.tagQty}'),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
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
        actions: [
          IconButton(icon: const Icon(Icons.info_outline), onPressed: () => _showInfo(context)),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(context)),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5,
          child: Image.file(File(photo.filePath)),
        ),
      ),
    );
  }
}
