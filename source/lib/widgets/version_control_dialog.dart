import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../db/db_helper.dart';
import '../utils/backup_util.dart';
import '../utils/build_info.dart';
import '../utils/storage_paths.dart';
import '../utils/theme.dart';

class VersionControlDialog extends StatefulWidget {
  const VersionControlDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (ctx) => const VersionControlDialog(),
    );
  }

  @override
  State<VersionControlDialog> createState() => _VersionControlDialogState();
}

class _VersionControlDialogState extends State<VersionControlDialog> {
  Map<String, int> _stats = {'aircraft': 0, 'photos': 0, 'tags': 0};
  bool _loading = true;
  bool _cleaningStorage = false;
  String? _storageCleanResult;

  final List<Map<String, dynamic>> _versionHistory = [
    {
      'version': 'v1.8.0 (Build 40)',
      'date': '27 Nov 2026',
      'current': true,
      'highlights': [
        'Version-wise control dashboard and backup manifest stamping',
        '1-tap automatic backup restore tool for seamless upgrades',
        'Single public storage engine (saves 50%+ device memory)',
        'Automatic storage duplicate purge to free phone space',
      ],
    },
    {
      'version': 'Update 20',
      'date': '20 Nov 2026',
      'current': false,
      'highlights': [
        'Location folder validation preventing illegal path characters (/ \\ : * ? " < > |)',
        'Real-time warning banner and 1-tap auto-fix chip',
        'Failsafe photo saving for folder names with dashes',
      ],
    },
    {
      'version': 'Update 19',
      'date': '30 Oct 2026',
      'current': false,
      'highlights': [
        'New DXB Workshop illustration on Splash & Home screen',
        'Build verification badge on Home screen',
        'Legacy SQLite database auto-cleaner for tag OCR records',
        'Streamlined 3-field tag editor (P/N, Description, Location)',
      ],
    },
    {
      'version': 'Update 18',
      'date': '30 Oct 2026',
      'current': false,
      'highlights': [
        'Fuzzy aviation maintenance dictionary auto-correction',
        'Gemini AI Vision cloud scan option for cursive handwriting',
      ],
    },
    {
      'version': 'Update 17',
      'date': '30 Oct 2026',
      'current': false,
      'highlights': [
        'Emirates QA/F/0363 aviation tag OCR engine',
        'Multi-camera ultra-wide 0.6x zoom support',
      ],
    },
    {
      'version': 'Update 16',
      'date': '29 Oct 2026',
      'current': false,
      'highlights': [
        'Single camera shutter button with automatic tag classification',
        'Tag Folder in Gallery showing Date, Time, User ID, and Location',
      ],
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final aircraftList = await DBHelper.instance.getAircraft();
    final photosList = await DBHelper.instance.getPhotos();
    final tagCount = photosList.where((p) => p.isTag == 1 || p.tagPartNo.isNotEmpty).length;
    if (mounted) {
      setState(() {
        _stats = {
          'aircraft': aircraftList.length,
          'photos': photosList.length,
          'tags': tagCount,
        };
        _loading = false;
      });
    }
  }

  Future<void> _cleanStorage() async {
    setState(() => _cleaningStorage = true);
    final count = await StoragePaths.cleanDuplicateStorageCopies();
    if (mounted) {
      setState(() {
        _cleaningStorage = false;
        _storageCleanResult = count > 0
            ? 'Purged $count redundant duplicate photos from storage!'
            : 'Storage is clean: No duplicate photos found.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: kPrimary.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.verified_outlined, color: kPrimary, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Version Control & Info', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text(
                  'Build: $kBuildId',
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.black54),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              // Version Status Card
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: Column(
                  children: [
                    _infoRow('App Release', 'v$kAppVersion (Build $kBuildNumber)'),
                    const Divider(height: 12),
                    _infoRow('Database Schema', 'Version $kDbVersion (Migrated & Up to date)'),
                    const Divider(height: 12),
                    _infoRow('Build Timestamp', kBuildDate),
                    const Divider(height: 12),
                    _infoRow('Signing Key', 'Official Release Key (Permanent)'),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Data & Storage Summary
              const Text('Data & Memory Control', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: kHeaderBlue)),
              const SizedBox(height: 8),
              if (_loading)
                const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
              else
                Row(
                  children: [
                    Expanded(child: _metricBox('Aircraft', '${_stats['aircraft']}', Icons.flight)),
                    const SizedBox(width: 8),
                    Expanded(child: _metricBox('Photos', '${_stats['photos']}', Icons.photo_library_outlined)),
                    const SizedBox(width: 8),
                    Expanded(child: _metricBox('Part Tags', '${_stats['tags']}', Icons.label_outline)),
                  ],
                ),
              const SizedBox(height: 10),

              // Storage optimization card
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFA7F3D0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.sd_storage_outlined, size: 18, color: Color(0xFF047857)),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Storage Engine: Single Public Copy',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF047857)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Photos are saved solely in Pictures/UUDS. No duplicate hidden copies exist in private app storage.',
                      style: TextStyle(fontSize: 11, color: Color(0xFF065F46)),
                    ),
                    if (_storageCleanResult != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        _storageCleanResult!,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF047857)),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF047857),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: _cleaningStorage
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.cleaning_services_outlined, size: 16),
                        label: const Text('Purge Duplicate Storage Now', style: TextStyle(fontSize: 11)),
                        onPressed: _cleaningStorage ? null : _cleanStorage,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Version History
              const Text('Version History & Changelog', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: kHeaderBlue)),
              const SizedBox(height: 8),
              ..._versionHistory.map((item) {
                final isCurrent = item['current'] == true;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isCurrent ? Colors.blue.withOpacity(0.06) : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: isCurrent ? Colors.blue.withOpacity(0.35) : Colors.black12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Text(item['version'], style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isCurrent ? kPrimary : Colors.black87)),
                              if (isCurrent) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(8)),
                                  child: const Text('CURRENT', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ],
                          ),
                          Text(item['date'], style: const TextStyle(fontSize: 11, color: Colors.black54)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ...(item['highlights'] as List<String>).map(
                        (h) => Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('• ', style: TextStyle(fontSize: 11, color: Colors.black54)),
                              Expanded(child: Text(h, style: const TextStyle(fontSize: 11, color: Colors.black87))),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
        Text(value, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.black87)),
      ],
    );
  }

  Widget _metricBox(String label, String count, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: kPrimary),
          const SizedBox(height: 4),
          Text(count, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.black54)),
        ],
      ),
    );
  }
}
