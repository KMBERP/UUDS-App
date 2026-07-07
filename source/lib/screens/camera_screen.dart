import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../db/db_helper.dart';
import '../models/models.dart';
import '../utils/ocr_util.dart';
import '../utils/page_transitions.dart';
import 'part_location_screen.dart';

class CameraScreen extends StatefulWidget {
  final Employee employee;
  final InspectionType type;
  final Aircraft aircraft;
  final PartLocation partLocation;

  const CameraScreen({
    super.key,
    required this.employee,
    required this.type,
    required this.aircraft,
    required this.partLocation,
  });

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _cameraIndex = 0;
  bool _ready = false;
  bool _capturing = false;
  String? _error;
  final List<InspectionPhoto> _sessionPhotos = []; // newest first
  final TextEditingController _remarksController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _error = 'No camera found on this device.');
        return;
      }
      _cameraIndex = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
      if (_cameraIndex < 0) _cameraIndex = 0;
      await _startController(_cameras[_cameraIndex]);
    } catch (e) {
      setState(() => _error = 'Camera error: $e');
    }
  }

  Future<void> _startController(CameraDescription desc) async {
    final controller = CameraController(desc, ResolutionPreset.high, enableAudio: false);
    await controller.initialize();
    if (!mounted) return;
    setState(() {
      _controller = controller;
      _ready = true;
    });
  }

  Future<void> _flipCamera() async {
    if (_cameras.length < 2 || !_ready) return;
    setState(() => _ready = false);
    await _controller?.dispose();
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _startController(_cameras[_cameraIndex]);
  }

  Future<Directory> _targetDirectory() async {
    final base = await getExternalStorageDirectory();
    final path =
        '${base!.path}/UUDS_Aero_Photos/${widget.aircraft.regNo}/${widget.type.label}/${widget.partLocation.name}';
    final dir = Directory(path);
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _captureAndSave() async {
    if (_controller == null || !_controller!.value.isInitialized || _capturing) return;
    setState(() => _capturing = true);
    try {
      final xfile = await _controller!.takePicture();
      final dir = await _targetDirectory();
      final ts = DateTime.now();
      final stamp = DateFormat('yyyyMMdd_HHmmss').format(ts);
      final fileName =
          'IMG_${widget.aircraft.regNo}_${widget.type.label}_${widget.partLocation.name.replaceAll(' ', '')}_$stamp.jpg';
      final destPath = '${dir.path}/$fileName';
      await File(xfile.path).copy(destPath);

      // Also save a copy into a "UUDS" album in the device's Gallery so the
      // photo is easy to find via the normal Gallery/Photos app or a file
      // manager, in addition to the app's own working copy above.
      try {
        await Gal.putImage(destPath, album: 'UUDS');
      } catch (_) {
        // Non-fatal: the app's own copy (used for all in-app features)
        // was already saved successfully above.
      }

      final record = InspectionPhoto(
        employeeName: widget.employee.name,
        aircraftReg: widget.aircraft.regNo,
        inspectionType: widget.type.label,
        partLocation: widget.partLocation.name,
        filePath: destPath,
        timestamp: ts.toIso8601String(),
        remarks: _remarksController.text.trim(),
      );
      final id = await DBHelper.instance.addPhoto(record);

      setState(() {
        _sessionPhotos.insert(
          0,
          InspectionPhoto(
            id: id,
            employeeName: record.employeeName,
            aircraftReg: record.aircraftReg,
            inspectionType: record.inspectionType,
            partLocation: record.partLocation,
            filePath: record.filePath,
            timestamp: record.timestamp,
            remarks: record.remarks,
          ),
        );
        _capturing = false;
      });
    } catch (e) {
      setState(() => _capturing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save photo: $e')));
      }
    }
  }

  Future<void> _deleteSessionPhoto(InspectionPhoto photo) async {
    await DBHelper.instance.deletePhoto(photo.id!);
    try {
      final f = File(photo.filePath);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    setState(() {
      _sessionPhotos.removeWhere((p) => p.id == photo.id);
    });
  }

  Future<void> _scanTag(InspectionPhoto photo) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: Colors.white)),
    );
    final extracted = await OcrUtil.extractTagFields(photo.filePath);
    if (mounted) Navigator.pop(context); // close loading spinner
    if (!mounted) return;

    final partNoCtrl = TextEditingController(text: extracted['partNo'] ?? '');
    final descCtrl = TextEditingController(text: extracted['description'] ?? '');
    final locCtrl = TextEditingController(text: extracted['location'] ?? '');
    final rawText = extracted['rawText'] ?? '';
    final error = extracted['error'];
    final qtyCtrl = TextEditingController(text: '1');

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
              TextField(controller: partNoCtrl, decoration: const InputDecoration(labelText: 'Part No.')),
              const SizedBox(height: 8),
              TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Description')),
              const SizedBox(height: 8),
              TextField(controller: locCtrl, decoration: const InputDecoration(labelText: 'Location (per tag)')),
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tag info saved')));
      }
    }
  }

  void _finish() {
    Navigator.of(context).pushReplacement(
      fadeSlideRoute(PartLocationScreen(
        employee: widget.employee,
        type: widget.type,
        aircraft: widget.aircraft,
      )),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${widget.aircraft.regNo} · ${widget.type.label} · ${widget.partLocation.name}',
          style: const TextStyle(fontSize: 14),
        ),
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
              ),
            )
          : !_ready
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    CameraPreview(_controller!),

                    // Remarks field
                    Positioned(
                      top: 8,
                      left: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(10)),
                        child: TextField(
                          controller: _remarksController,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Remarks (optional)',
                            hintStyle: TextStyle(color: Colors.white60),
                            isDense: true,
                          ),
                        ),
                      ),
                    ),

                    // Thumbnail strip (above the button row), scrolls right-to-left
                    Positioned(
                      bottom: 118,
                      left: 0,
                      right: 0,
                      height: 72,
                      child: _sessionPhotos.isEmpty
                          ? const SizedBox.shrink()
                          : ListView.builder(
                              reverse: true,
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              itemCount: _sessionPhotos.length,
                              itemBuilder: (ctx, i) {
                                final photo = _sessionPhotos[i];
                                return Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      GestureDetector(
                                        onLongPress: () => _scanTag(photo),
                                        child: Container(
                                          width: 64,
                                          height: 64,
                                          decoration: BoxDecoration(
                                            border: Border.all(color: Colors.white, width: 2),
                                            borderRadius: BorderRadius.circular(8),
                                            image: DecorationImage(image: FileImage(File(photo.filePath)), fit: BoxFit.cover),
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        top: -6,
                                        right: -6,
                                        child: GestureDetector(
                                          onTap: () => _deleteSessionPhoto(photo),
                                          child: Container(
                                            width: 22,
                                            height: 22,
                                            decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                            child: const Icon(Icons.close, color: Colors.white, size: 14),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                    if (_sessionPhotos.isNotEmpty)
                      Positioned(
                        bottom: 192,
                        left: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(16)),
                          child: Text(
                            '${_sessionPhotos.length} photo(s) · long-press one to scan tag',
                            style: const TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                        ),
                      ),

                    // Camera flip button (left side)
                    Positioned(
                      bottom: 36,
                      left: 24,
                      child: GestureDetector(
                        onTap: _flipCamera,
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.black45,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white54, width: 2),
                          ),
                          child: const Icon(Icons.flip_camera_android_rounded, color: Colors.white, size: 28),
                        ),
                      ),
                    ),

                    // Capture button (center)
                    Positioned(
                      bottom: 26,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: GestureDetector(
                          onTap: _captureAndSave,
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              border: Border.all(color: _capturing ? Colors.grey : Colors.white70, width: 4),
                              boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4))],
                            ),
                            child: _capturing
                                ? const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(strokeWidth: 3))
                                : const Icon(Icons.camera_alt, size: 34, color: Colors.black87),
                          ),
                        ),
                      ),
                    ),

                    // Finish button (bottom-right of capture button) - just navigates back
                    Positioned(
                      bottom: 36,
                      right: 24,
                      child: GestureDetector(
                        onTap: _finish,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 3))],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle, color: Colors.white, size: 22),
                              SizedBox(width: 6),
                              Text('Finish', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
