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
  final List<InspectionPhoto> _sessionPhotos = [];
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
    // Use parent of external storage to survive app uninstall
    final rootDir = Directory('${base!.parent.path}/UUDS');
    final path =
        '${rootDir.path}/Aircrafts/${widget.aircraft.regNo}/${widget.type.label}/${widget.partLocation.name}';
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

      try {
        await Gal.putImage(destPath, album: 'UUDS');
      } catch (_) {}

      final record = InspectionPhoto(
        employeeName: widget.employee.name,
        aircraftReg: widget.aircraft.regNo,
        inspectionType: widget.type.label,
        partLocation: widget.partLocation.name,
        filePath: destPath,
        timestamp: ts.toIso8601String(),
        remarks: _remarksController.text.trim(),
      );

      final ocr = await OCRUtil.recognizeText(destPath);
      if (ocr != null) {
        record.tagPartNo = ocr['partNo'] ?? '';
        record.tagDescription = ocr['description'] ?? '';
        record.tagLocation = ocr['location'] ?? '';
        record.tagQty = ocr['qty'] ?? '';
      }

      await DBHelper.instance.insertPhoto(record);
      setState(() => _sessionPhotos.insert(0, record));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Capture failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _finish() async {
    if (_sessionPhotos.isEmpty) {
      Navigator.pop(context);
      return;
    }
    Navigator.pop(context, true);
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
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _error != null
                  ? Center(child: Text(_error!, style: const TextStyle(color: Colors.white)))
                  : !_ready || _controller == null
                      ? const Center(child: CircularProgressIndicator())
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: CameraPreview(_controller!),
                        ),
            ),
            if (_sessionPhotos.isNotEmpty)
              Container(
                height: 72,
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _sessionPhotos.length,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemBuilder: (ctx, i) {
                    final p = _sessionPhotos[i];
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(File(p.filePath), width: 56, height: 56, fit: BoxFit.cover),
                      ),
                    );
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.cameraswitch, color: Colors.white),
                    onPressed: _flipCamera,
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: _captureAndSave,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                          color: _capturing ? Colors.grey : Colors.white.withOpacity(0.2),
                        ),
                        child: Center(
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _capturing ? Colors.grey : Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.check_circle, color: Colors.white, size: 32),
                    onPressed: _finish,
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
