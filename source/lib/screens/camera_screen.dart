import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../db/db_helper.dart';
import '../models/models.dart';
import '../utils/build_info.dart';
import '../utils/tag_scan_dialog.dart';
import '../utils/page_transitions.dart';
import '../utils/storage_paths.dart';
import '../utils/text_formatters.dart';
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
  int _galleryPublishFailures = 0;
  final List<String> _galleryPublishErrors = [];

  // Flashlight / Torch
  FlashMode _flashMode = FlashMode.off;

  // Zoom
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _zoom = 1.0;
  double _zoomStartValue = 1.0;

  // Tag alignment frame mode
  bool _tagGuideVisible = false;

  // Tap-to-focus indicator (technical reticle shown where user tapped)
  Offset? _focusPoint;

  // Hardware camera button & side key channel
  static const MethodChannel _hardwareKeysChannel = MethodChannel('uuds/hardware_keys');

  @override
  void initState() {
    super.initState();
    _initCamera();
    _initHardwareKeys();
  }

  void _initHardwareKeys() {
    _hardwareKeysChannel.invokeMethod('setCameraScreenActive', {'active': true});
    _hardwareKeysChannel.setMethodCallHandler((call) async {
      if (call.method == 'cameraButtonPressed') {
        if (!_capturing && mounted) {
          _captureAndSave(isTag: _tagGuideVisible);
        }
      }
    });
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
    final controller = CameraController(desc, ResolutionPreset.veryHigh, enableAudio: false);
    await controller.initialize();
    if (!mounted) return;
    final minZoom = await controller.getMinZoomLevel();
    final maxZoom = await controller.getMaxZoomLevel();

    // Enable continuous auto-focus and auto-exposure
    try {
      await controller.setFocusMode(FocusMode.auto);
      await controller.setExposureMode(ExposureMode.auto);
    } catch (_) {}

    setState(() {
      _controller = controller;
      _ready = true;
      _minZoom = minZoom;
      _maxZoom = maxZoom;
      _zoom = minZoom;
      _flashMode = FlashMode.off;
    });
  }

  Future<void> _toggleTorch() async {
    if (_controller == null || !_ready) return;
    final nextMode = _flashMode == FlashMode.torch ? FlashMode.off : FlashMode.torch;
    try {
      await _controller!.setFlashMode(nextMode);
      setState(() => _flashMode = nextMode);
      HapticFeedback.lightImpact();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Torch not supported: $e')));
      }
    }
  }

  Future<void> _flipCamera() async {
    if (_cameras.length < 2 || !_ready) return;
    setState(() => _ready = false);
    await _controller?.dispose();
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _startController(_cameras[_cameraIndex]);
  }

  void _onScaleStart(ScaleStartDetails details) {
    _zoomStartValue = _zoom;
  }

  Future<void> _onScaleUpdate(ScaleUpdateDetails details) async {
    if (_controller == null || !_ready || _maxZoom <= _minZoom) return;
    final newZoom = (_zoomStartValue * details.scale).clamp(_minZoom, _maxZoom);
    if (newZoom == _zoom) return;
    _zoom = newZoom;
    setState(() {});
    await _controller!.setZoomLevel(_zoom);
  }

  Future<void> _setZoom(double value) async {
    if (_controller == null || !_ready) return;
    final clamped = value.clamp(_minZoom, _maxZoom);
    setState(() => _zoom = clamped);
    await _controller!.setZoomLevel(clamped);
  }

  void _stepZoom(double delta) {
    final target = (_zoom + delta).clamp(_minZoom, _maxZoom);
    _setZoom(target);
    HapticFeedback.selectionClick();
  }

  /// Tapping the preview locks focus and exposure at that exact point
  Future<void> _onTapToFocus(TapUpDetails details, BoxConstraints constraints) async {
    if (_controller == null || !_ready) return;
    final point = Offset(
      details.localPosition.dx / constraints.maxWidth,
      details.localPosition.dy / constraints.maxHeight,
    );
    setState(() => _focusPoint = details.localPosition);
    try {
      await _controller!.setFocusPoint(point);
      await _controller!.setExposurePoint(point);
      await _controller!.setFocusMode(FocusMode.auto);
      await _controller!.setExposureMode(ExposureMode.auto);
      HapticFeedback.selectionClick();
    } catch (_) {}
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _focusPoint = null);
    });
  }

  Future<Directory> _targetDirectory({bool isTag = false}) async {
    return StoragePaths.photoDirectory(
      aircraftReg: widget.aircraft.regNo,
      inspectionTypeLabel: widget.type.label,
      location: widget.partLocation.name,
      isTag: isTag,
    );
  }

  Future<void> _captureAndSave({bool isTag = false}) async {
    if (_controller == null || !_controller!.value.isInitialized || _capturing) return;
    setState(() => _capturing = true);
    HapticFeedback.mediumImpact();
    try {
      // Briefly lock focus to guarantee crisp exposure without shutter blur
      try {
        await _controller!.setFocusMode(FocusMode.locked);
      } catch (_) {}

      final xfile = await _controller!.takePicture();

      // Restore auto focus
      try {
        await _controller!.setFocusMode(FocusMode.auto);
      } catch (_) {}

      final savedPhoto = await _saveSourceFile(xfile.path, isTag: isTag);
      if (savedPhoto == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save photo.')));
      } else if (savedPhoto != null && isTag) {
        // Automatically prompt tag OCR scanning for tag photos
        await _scanTag(savedPhoto);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save photo: $e')));
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _importFromGallery({bool isTag = false}) async {
    if (_capturing) return;
    List<XFile> picked;
    try {
      picked = await ImagePicker().pickMultiImage(imageQuality: 92);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open gallery: $e')));
      }
      return;
    }
    if (picked.isEmpty) return;

    setState(() => _capturing = true);
    var imported = 0;
    InspectionPhoto? lastImported;
    for (final xfile in picked) {
      final photo = await _saveSourceFile(xfile.path, isTag: isTag);
      if (photo != null) {
        imported++;
        lastImported = photo;
      }
    }
    if (mounted) {
      setState(() => _capturing = false);
      final destFolder = isTag ? 'Part_Tags' : widget.partLocation.name;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            imported == picked.length
                ? 'Imported $imported photo${imported == 1 ? '' : 's'} into $destFolder.'
                : 'Imported $imported of ${picked.length} photos into $destFolder.',
          ),
        ),
      );
      if (isTag && lastImported != null && imported == 1) {
        await _scanTag(lastImported);
      }
    }
  }

  /// Copies source into working directory and mirrors to public MediaStore.
  /// If [isTag] is true, saves into dedicated Part_Tags directory.
  Future<InspectionPhoto?> _saveSourceFile(String sourcePath, {bool isTag = false}) async {
    try {
      final dir = await _targetDirectory(isTag: isTag);
      final ts = DateTime.now();
      final stamp = DateFormat('yyyyMMdd_HHmmss_SSS').format(ts);
      final prefix = isTag ? 'TAG' : 'IMG';
      final fileName =
          '${prefix}_${widget.aircraft.regNo}_${widget.type.label}_${widget.partLocation.name.replaceAll(' ', '')}_$stamp.jpg';
      final destPath = '${dir.path}/$fileName';
      await File(sourcePath).copy(destPath);

      // Mirror into public Gallery
      final published = await StoragePaths.publishToGallery(
        sourcePath: destPath,
        aircraftReg: widget.aircraft.regNo,
        inspectionTypeLabel: widget.type.label,
        location: widget.partLocation.name,
        fileName: fileName,
        isTag: isTag,
      );
      if (!published.success) {
        _galleryPublishFailures++;
        if (published.error != null && !_galleryPublishErrors.contains(published.error)) {
          _galleryPublishErrors.add(published.error!);
        }
      }

      final record = InspectionPhoto(
        employeeName: widget.employee.name,
        aircraftReg: widget.aircraft.regNo,
        inspectionType: widget.type.label,
        partLocation: widget.partLocation.name,
        filePath: destPath,
        timestamp: ts.toIso8601String(),
        remarks: _remarksController.text.trim(),
        isTag: isTag ? 1 : 0,
      );
      final id = await DBHelper.instance.addPhoto(record);

      final newPhoto = InspectionPhoto(
        id: id,
        employeeName: record.employeeName,
        aircraftReg: record.aircraftReg,
        inspectionType: record.inspectionType,
        partLocation: record.partLocation,
        filePath: record.filePath,
        timestamp: record.timestamp,
        remarks: record.remarks,
        isTag: record.isTag,
      );

      if (mounted) {
        setState(() {
          _sessionPhotos.insert(0, newPhoto);
        });
      }
      return newPhoto;
    } catch (_) {
      return null;
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
    final updated = await showTagScanDialog(context, photo);
    if (updated) {
      final refreshed = await DBHelper.instance.getPhotos();
      final current = refreshed.firstWhere((p) => p.id == photo.id, orElse: () => photo);
      setState(() {
        final idx = _sessionPhotos.indexWhere((p) => p.id == photo.id);
        if (idx != -1) _sessionPhotos[idx] = current;
      });
    }
  }

  Future<void> _finish() async {
    final photoCount = _sessionPhotos.length;
    final tagCount = _sessionPhotos.where((p) => p.isTag == 1).length;
    final partCount = photoCount - tagCount;

    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('Session Complete'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                photoCount == 0
                    ? 'No photos were taken this session.'
                    : '$photoCount photo${photoCount == 1 ? '' : 's'} saved successfully ($partCount parts, $tagCount tags).',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              const SizedBox(height: 12),
              _infoRow('Inspector:', widget.employee.name),
              _infoRow('Aircraft:', widget.aircraft.regNo),
              _infoRow('Type:', widget.type.label),
              _infoRow('Location:', widget.partLocation.name),
              if (photoCount > 0) ...[
                const SizedBox(height: 12),
                const Text('Public Folders:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Text(
                    'Parts: Pictures/UUDS/Photos/${widget.aircraft.regNo}/${widget.type.label}/${widget.partLocation.name}\n'
                    'Tags: Pictures/UUDS/Part_Tags/${widget.aircraft.regNo}/${widget.type.label}/${widget.partLocation.name}',
                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      fadeSlideRoute(PartLocationScreen(
        employee: widget.employee,
        type: widget.type,
        aircraft: widget.aircraft,
      )),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: const TextStyle(fontSize: 13, color: Colors.black54)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _hardwareKeysChannel.invokeMethod('setCameraScreenActive', {'active': false});
    _hardwareKeysChannel.setMethodCallHandler(null);
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
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            tooltip: _flashMode == FlashMode.torch ? 'Torch ON' : 'Torch OFF',
            icon: Icon(
              _flashMode == FlashMode.torch ? Icons.flash_on : Icons.flash_off,
              color: _flashMode == FlashMode.torch ? Colors.amber : Colors.white,
            ),
            onPressed: _toggleTorch,
          ),
          IconButton(
            tooltip: _tagGuideVisible ? 'Hide Tag Frame' : 'Show Tag Frame',
            icon: Icon(
              Icons.crop_free,
              color: _tagGuideVisible ? Colors.amber : Colors.white70,
            ),
            onPressed: () {
              setState(() => _tagGuideVisible = !_tagGuideVisible);
              HapticFeedback.selectionClick();
            },
          ),
          IconButton(
            tooltip: 'Import from gallery',
            icon: const Icon(Icons.add_photo_alternate_outlined),
            onPressed: _capturing ? null : () => _importFromGallery(isTag: _tagGuideVisible),
          ),
        ],
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
                    LayoutBuilder(
                      builder: (context, constraints) {
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onScaleStart: _onScaleStart,
                          onScaleUpdate: _onScaleUpdate,
                          onTapUp: (details) => _onTapToFocus(details, constraints),
                          child: CameraPreview(_controller!),
                        );
                      },
                    ),

                    // Technical corner-bracket focus reticle
                    if (_focusPoint != null)
                      Positioned(
                        left: _focusPoint!.dx - 36,
                        top: _focusPoint!.dy - 36,
                        child: IgnorePointer(
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.amberAccent, width: 2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Center(
                              child: Icon(Icons.add, color: Colors.amberAccent, size: 20),
                            ),
                          ),
                        ),
                      ),

                    // Tag Framing Guide Overlay (when tag scanning mode is active)
                    if (_tagGuideVisible)
                      Center(
                        child: IgnorePointer(
                          child: Container(
                            width: MediaQuery.of(context).size.width * 0.85,
                            height: 180,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.amberAccent, width: 2.5),
                              borderRadius: BorderRadius.circular(12),
                              color: Colors.amber.withOpacity(0.08),
                            ),
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.qr_code_scanner, color: Colors.amberAccent, size: 36),
                                SizedBox(height: 6),
                                Text(
                                  'ALIGN PART TAG INSIDE THIS FRAME',
                                  style: TextStyle(
                                    color: Colors.amberAccent,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    // Remarks field
                    Positioned(
                      top: 8,
                      left: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
                        child: TextField(
                          controller: _remarksController,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          textCapitalization: TextCapitalization.characters,
                          inputFormatters: [upperCaseInputFormatter],
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Remarks (optional)',
                            hintStyle: TextStyle(color: Colors.white60),
                            isDense: true,
                          ),
                        ),
                      ),
                    ),

                    // Discrete Zoom Buttons (-1, -0.5, 1.0x, +0.5, +1)
                    Positioned(
                      bottom: 200,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: _buildZoomBar(),
                      ),
                    ),

                    // Thumbnail strip (above the button row)
                    Positioned(
                      bottom: 114,
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
                                final isTag = photo.isTag == 1;
                                return Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      GestureDetector(
                                        onTap: () => _scanTag(photo),
                                        child: Container(
                                          width: 64,
                                          height: 64,
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                              color: isTag ? Colors.amberAccent : Colors.white,
                                              width: isTag ? 2.5 : 1.5,
                                            ),
                                            borderRadius: BorderRadius.circular(8),
                                            image: DecorationImage(
                                              image: ResizeImage(FileImage(File(photo.filePath)), width: 128),
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                        ),
                                      ),
                                      // Tag indicator badge
                                      if (isTag)
                                        Positioned(
                                          bottom: 2,
                                          left: 2,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: Colors.amberAccent,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: const Text(
                                              'TAG',
                                              style: TextStyle(
                                                color: Colors.black,
                                                fontSize: 9,
                                                fontWeight: FontWeight.w900,
                                              ),
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

                    // Controls row at bottom
                    Positioned(
                      bottom: 22,
                      left: 16,
                      right: 16,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Flip Camera
                          GestureDetector(
                            onTap: _flipCamera,
                            child: Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: Colors.black45,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white54, width: 2),
                              ),
                              child: const Icon(Icons.flip_camera_android_rounded, color: Colors.white, size: 24),
                            ),
                          ),

                          // DUAL CAPTURE BUTTONS: PART PHOTO & TAG PHOTO
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 1. Part Photo Shutter Button
                              GestureDetector(
                                onTap: () => _captureAndSave(isTag: false),
                                child: Container(
                                  width: 74,
                                  height: 74,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white,
                                    border: Border.all(color: _capturing ? Colors.grey : Colors.blue.shade100, width: 4),
                                    boxShadow: const [
                                      BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4)),
                                    ],
                                  ),
                                  child: _capturing
                                      ? const Padding(padding: EdgeInsets.all(18), child: CircularProgressIndicator(strokeWidth: 3))
                                      : const Icon(Icons.camera_alt, size: 34, color: Color(0xFF0B3D91)),
                                ),
                              ),

                              const SizedBox(width: 14),

                              // 2. Dedicated Part Tag Capture Button (Saves to Part_Tags folder)
                              GestureDetector(
                                onTap: () => _captureAndSave(isTag: true),
                                child: Container(
                                  width: 74,
                                  height: 74,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: const Color(0xFFE65100),
                                    border: Border.all(color: Colors.amberAccent, width: 3),
                                    boxShadow: const [
                                      BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4)),
                                    ],
                                  ),
                                  child: const Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.qr_code_scanner, size: 28, color: Colors.white),
                                      Text(
                                        'TAG',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 10,
                                          letterSpacing: 1,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),

                          // Finish Session Button
                          GestureDetector(
                            onTap: _finish,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.green,
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 3))],
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_circle, color: Colors.white, size: 20),
                                  SizedBox(width: 4),
                                  Text('Finish', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  /// Discrete zoom buttons (-1, -0.5, 1.0x, +0.5, +1)
  Widget _buildZoomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.65),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _zoomStepBtn('-1.0', () => _stepZoom(-1.0)),
          const SizedBox(width: 4),
          _zoomStepBtn('-0.5', () => _stepZoom(-0.5)),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              _setZoom(_minZoom);
              HapticFeedback.selectionClick();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF0B3D91),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white38),
              ),
              child: Text(
                '${_zoom.toStringAsFixed(1)}x',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _zoomStepBtn('+0.5', () => _stepZoom(0.5)),
          const SizedBox(width: 4),
          _zoomStepBtn('+1.0', () => _stepZoom(1.0)),
        ],
      ),
    );
  }

  Widget _zoomStepBtn(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
