import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../db/db_helper.dart';
import '../models/models.dart';
import 'ocr_util.dart';
import 'text_formatters.dart';

/// Runs OCR on [photo], shows the "review & correct" dialog, and saves
/// whatever the user confirms via [DBHelper.updatePhotoTagFields].
///
/// Shared by the camera screen (scanning a tag right after taking the
/// photo) and the Gallery (scanning - or re-scanning - a tag on a photo
/// that was taken earlier, e.g. if scanning it was missed at the time).
///
/// Returns true if the user saved tag info, false if they cancelled.
Future<bool> showTagScanDialog(BuildContext context, InspectionPhoto photo) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator(color: Colors.white)),
  );
  final extracted = await OcrUtil.extractTagFields(photo.filePath);
  if (context.mounted) Navigator.pop(context); // close loading spinner
  if (!context.mounted) return false;

  final partNoCtrl = TextEditingController(text: (extracted['partNo'] ?? photo.tagPartNo).toUpperCase());
  final descCtrl = TextEditingController(text: (extracted['description'] ?? photo.tagDescription).toUpperCase());
  final locCtrl = TextEditingController(text: (extracted['location'] ?? photo.tagLocation).toUpperCase());
  final rawText = extracted['rawText'] ?? '';
  final error = extracted['error'];
  final qtyCtrl = TextEditingController(text: photo.tagQty.isNotEmpty ? photo.tagQty : '1');

  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Tag Info (review & correct)'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('Scan error: $error', style: const TextStyle(color: Colors.red, fontSize: 12)),
              ),
            TextField(
              controller: partNoCtrl,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [upperCaseInputFormatter],
              decoration: const InputDecoration(labelText: 'Part No.'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: descCtrl,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [upperCaseInputFormatter],
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: locCtrl,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [upperCaseInputFormatter],
              decoration: const InputDecoration(labelText: 'Location (per tag)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: qtyCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Qty'),
            ),
            const SizedBox(height: 10),
            const Text(
              'Handwritten text may not scan perfectly — please check before saving.',
              style: TextStyle(fontSize: 11, color: Colors.black45),
            ),
            if (rawText.isNotEmpty) ...[
              const SizedBox(height: 10),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Show raw scanned text', style: TextStyle(fontSize: 12)),
                children: [
                  Container(
                    width: double.maxFinite,
                    padding: const EdgeInsets.all(8),
                    color: Colors.black12,
                    child: Text(rawText, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                  ),
                ],
              ),
            ] else if (error == null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'No text detected at all in this photo — try retaking it closer, brighter, and with the tag facing the camera right-side up.',
                  style: TextStyle(fontSize: 11, color: Colors.deepOrange),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
      ],
    ),
  );

  if (result == true) {
    await DBHelper.instance.updatePhotoTagFields(
      photo.id!,
      partNoCtrl.text.trim(),
      descCtrl.text.trim(),
      locCtrl.text.trim(),
      qtyCtrl.text.trim(),
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tag info saved')));
    }
    return true;
  }
  return false;
}
