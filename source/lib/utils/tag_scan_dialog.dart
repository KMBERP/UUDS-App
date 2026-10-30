import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../db/db_helper.dart';
import '../models/models.dart';
import '../utils/theme.dart';
import 'ocr_util.dart';
import 'text_formatters.dart';

/// Runs OCR on [photo], shows an interactive "review & 1-tap fill" dialog,
/// and saves confirmed values via [DBHelper.updatePhotoTagFields].
///
/// Features:
/// - Side-by-side or scrollable tag photo thumbnail preview
/// - Auto-extracted fields (Part No, Description, Location, Qty)
/// - Interactive Candidate Chips: Tap-to-assign any recognized OCR line
///   to Part No, Description, Location, or Qty in one single tap!
Future<bool> showTagScanDialog(BuildContext context, InspectionPhoto photo) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator(color: Colors.white)),
  );

  final extracted = await OcrUtil.extractTagFields(photo.filePath);
  if (context.mounted) Navigator.pop(context); // close loading spinner
  if (!context.mounted) return false;

  final partNoCtrl = TextEditingController(text: (extracted['partNo']?.toString().isNotEmpty == true ? extracted['partNo'] : photo.tagPartNo).toString().toUpperCase());
  final descCtrl = TextEditingController(text: (extracted['description']?.toString().isNotEmpty == true ? extracted['description'] : photo.tagDescription).toString().toUpperCase());
  final locCtrl = TextEditingController(text: (extracted['location']?.toString().isNotEmpty == true ? extracted['location'] : photo.tagLocation).toString().toUpperCase());
  final qtyCtrl = TextEditingController(
    text: photo.tagQty.isNotEmpty
        ? photo.tagQty
        : ((extracted['tagQty'] != null && extracted['tagQty'].toString().isNotEmpty) ? extracted['tagQty'].toString() : '1'),
  );

  final rawText = (extracted['rawText'] ?? '').toString();
  final error = extracted['error']?.toString();
  final List<String> candidates = List<String>.from(extracted['candidates'] ?? []);

  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setDialogState) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          titlePadding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
          contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFE65100),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.qr_code_scanner, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Tag OCR Review',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: kHeaderBlue),
                ),
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
                  // Photo thumbnail banner
                  if (File(photo.filePath).existsSync())
                    Container(
                      height: 110,
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.amber.shade300, width: 2),
                        image: DecorationImage(
                          image: FileImage(File(photo.filePath)),
                          fit: BoxFit.cover,
                        ),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        alignment: Alignment.bottomRight,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            photo.aircraftReg,
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),

                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text('Scan error: $error', style: const TextStyle(color: Colors.red, fontSize: 12)),
                    ),

                  // Part Number Field
                  TextField(
                    controller: partNoCtrl,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [upperCaseInputFormatter],
                    decoration: InputDecoration(
                      labelText: 'Part Number (P/N)',
                      labelStyle: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0B3D91)),
                      filled: true,
                      fillColor: Colors.blue.shade50.withOpacity(0.5),
                      prefixIcon: const Icon(Icons.tag, color: Color(0xFF0B3D91), size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Description Field
                  TextField(
                    controller: descCtrl,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [upperCaseInputFormatter],
                    decoration: InputDecoration(
                      labelText: 'Description',
                      labelStyle: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0B3D91)),
                      filled: true,
                      fillColor: Colors.blue.shade50.withOpacity(0.5),
                      prefixIcon: const Icon(Icons.description, color: Color(0xFF0B3D91), size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Location and Qty in one row
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: locCtrl,
                          textCapitalization: TextCapitalization.characters,
                          inputFormatters: [upperCaseInputFormatter],
                          decoration: InputDecoration(
                            labelText: 'Tag Location',
                            labelStyle: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0B3D91)),
                            filled: true,
                            fillColor: Colors.blue.shade50.withOpacity(0.5),
                            prefixIcon: const Icon(Icons.place, color: Color(0xFF0B3D91), size: 18),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: qtyCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Qty',
                            labelStyle: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0B3D91)),
                            filled: true,
                            fillColor: Colors.blue.shade50.withOpacity(0.5),
                            prefixIcon: const Icon(Icons.numbers, color: Color(0xFF0B3D91), size: 18),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Interactive Candidate Chips Section
                  if (candidates.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.touch_app, size: 16, color: Colors.amber.shade900),
                          const SizedBox(width: 6),
                          Text(
                            'DETECTED TEXT (1-TAP TO ASSIGN):',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber.shade900,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: candidates.map((cand) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 1)),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                cand,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: Colors.black87),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _assignPill('P/N', Colors.blue, () {
                                    setDialogState(() {
                                      partNoCtrl.text = cand.toUpperCase().trim();
                                    });
                                    HapticFeedback.selectionClick();
                                  }),
                                  const SizedBox(width: 4),
                                  _assignPill('Desc', Colors.indigo, () {
                                    setDialogState(() {
                                      descCtrl.text = cand.toUpperCase().trim();
                                    });
                                    HapticFeedback.selectionClick();
                                  }),
                                  const SizedBox(width: 4),
                                  _assignPill('Loc', Colors.teal, () {
                                    setDialogState(() {
                                      locCtrl.text = cand.toUpperCase().trim();
                                    });
                                    HapticFeedback.selectionClick();
                                  }),
                                  const SizedBox(width: 4),
                                  _assignPill('Qty', Colors.orange, () {
                                    final digits = RegExp(r'\d+').firstMatch(cand);
                                    setDialogState(() {
                                      qtyCtrl.text = digits != null ? digits.group(0)! : '1';
                                    });
                                    HapticFeedback.selectionClick();
                                  }),
                                ],
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],

                  if (rawText.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('View All Scanned Lines', style: TextStyle(fontSize: 11.5, color: Colors.black54)),
                      children: [
                        Container(
                          width: double.maxFinite,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Text(
                            rawText,
                            style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace', color: Colors.black87),
                          ),
                        ),
                      ],
                    ),
                  ],
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
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.check, size: 18, color: Colors.white),
              label: const Text('Save Tag Info', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tag information saved successfully'),
          backgroundColor: Color(0xFF2E7D32),
        ),
      );
    }
    return true;
  }
  return false;
}

Widget _assignPill(String label, MaterialColor color, VoidCallback onTap) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.shade300),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.bold,
          color: color.shade800,
        ),
      ),
    ),
  );
}
