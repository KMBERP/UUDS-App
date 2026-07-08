import 'dart:io';
import 'package:excel/excel.dart' as xl;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../db/db_helper.dart';
import '../models/models.dart';
import '../utils/storage_paths.dart';
import '../utils/theme.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/pressable_button.dart';

enum ReportKind { tagsReport, aircraftSummary, partLocation }

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  ReportKind _kind = ReportKind.tagsReport;
  DateTimeRange? _range;
  String? _selectedInspector; // null = All
  bool _loading = true;
  bool _exporting = false;
  bool _emailing = false;
  List<InspectionPhoto> _photos = [];
  List<Employee> _employees = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    String? from, to;
    if (_range != null) {
      from = DateTime(_range!.start.year, _range!.start.month, _range!.start.day).toIso8601String();
      to = DateTime(_range!.end.year, _range!.end.month, _range!.end.day, 23, 59, 59).toIso8601String();
    }
    final list = await DBHelper.instance.getPhotos(fromDate: from, toDate: to);
    final employees = await DBHelper.instance.getEmployees();
    setState(() {
      _photos = list;
      _employees = employees;
      _loading = false;
    });
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _range,
    );
    if (range != null) {
      setState(() => _range = range);
      _load();
    }
  }

  String _inspectorButtonLabel() {
    if (_selectedInspector == null) return 'Inspector: All';
    final emp = _employees.firstWhere(
      (e) => e.name == _selectedInspector,
      orElse: () => Employee(name: _selectedInspector!),
    );
    if (emp.idNumber.isNotEmpty) return 'Inspector: UUDS-${emp.idNumber}';
    return 'Inspector: ${_selectedInspector!.split(' ').first}';
  }

  Future<void> _pickInspector() async {
    final chosen = await showDialog<String?>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Filter by Inspector'),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, null), child: const Text('All Inspectors')),
          ..._employees.map((e) => SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, e.name),
            child: Text(e.idNumber.isEmpty ? e.name : '${e.name} (UUDS-${e.idNumber})'),
          )),
        ],
      ),
    );
    setState(() => _selectedInspector = chosen);
  }

  /// Only photos where a tag was actually scanned/entered represent a real
  /// distinct part — this is what the reports should count, not every
  /// raw photo (several photos are often taken of the same part).
  List<InspectionPhoto> get _taggedPhotos {
    return _photos.where((p) {
      if (p.tagPartNo.trim().isEmpty) return false;
      if (_selectedInspector != null && p.employeeName != _selectedInspector) return false;
      return true;
    }).toList();
  }

  List<String> get _headers {
    switch (_kind) {
      case ReportKind.tagsReport:
        return ['S No', 'Date/Time', 'A/C', 'Location', 'Tag Part No', 'Tag Description', 'Tag Location', 'Tag Qty', 'Inspector', 'Remarks'];
      case ReportKind.aircraftSummary:
        return ['S No', 'Aircraft Reg No', 'Receiving Tags', 'Dispatch Tags', 'Total'];
      case ReportKind.partLocation:
        return ['S No', 'Part Location', 'Tag Count'];
    }
  }

  List<double> get _columnWidths {
    switch (_kind) {
      case ReportKind.tagsReport:
        return [45, 110, 65, 100, 100, 130, 100, 50, 110, 120];
      case ReportKind.aircraftSummary:
        return [45, 150, 120, 120, 80];
      case ReportKind.partLocation:
        return [45, 220, 100];
    }
  }

  List<List<String>> get _rows {
    final tagged = _taggedPhotos;
    switch (_kind) {
      case ReportKind.tagsReport:
        final list = tagged
            .map((p) => [
                  DateFormat('dd-MM-yyyy HH:mm').format(DateTime.parse(p.timestamp)),
                  p.aircraftReg,
                  p.partLocation,
                  p.tagPartNo,
                  p.tagDescription,
                  p.tagLocation,
                  p.tagQty,
                  p.employeeName,
                  p.remarks,
                ])
            .toList();
        return [for (int i = 0; i < list.length; i++) ['${i + 1}', ...list[i]]];
      case ReportKind.aircraftSummary:
        final Map<String, Map<String, int>> summary = {};
        for (final p in tagged) {
          summary.putIfAbsent(p.aircraftReg, () => {'Receiving': 0, 'Dispatch': 0});
          summary[p.aircraftReg]![p.inspectionType] = (summary[p.aircraftReg]![p.inspectionType] ?? 0) + 1;
        }
        final entries = summary.entries.toList();
        return [
          for (int i = 0; i < entries.length; i++)
            [
              '${i + 1}',
              entries[i].key,
              '${entries[i].value['Receiving']}',
              '${entries[i].value['Dispatch']}',
              '${(entries[i].value['Receiving'] ?? 0) + (entries[i].value['Dispatch'] ?? 0)}',
            ]
        ];
      case ReportKind.partLocation:
        final Map<String, int> byLocation = {};
        for (final p in tagged) {
          byLocation[p.partLocation] = (byLocation[p.partLocation] ?? 0) + 1;
        }
        final entries = byLocation.entries.toList();
        return [for (int i = 0; i < entries.length; i++) ['${i + 1}', entries[i].key, '${entries[i].value}']];
    }
  }

  String get _reportTitle {
    switch (_kind) {
      case ReportKind.tagsReport:
        return 'Tags Report';
      case ReportKind.aircraftSummary:
        return 'Aircraft-wise Summary';
      case ReportKind.partLocation:
        return 'Part Location Report';
    }
  }

  Future<void> _exportExcel() async {
    setState(() => _exporting = true);
    try {
      final excelFile = xl.Excel.createExcel();
      final sheet = excelFile['Report'];
      sheet.appendRow(_headers.map((h) => xl.TextCellValue(h)).toList());
      for (final row in _rows) {
        sheet.appendRow(row.map((c) => xl.TextCellValue(c)).toList());
      }
      if (excelFile.sheets.containsKey('Sheet1')) {
        excelFile.delete('Sheet1');
      }

      final reportsDir = await StoragePaths.reportsDirectory();
      final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = '${_reportTitle.replaceAll(' ', '_')}_$stamp.xlsx';
      final file = File('${reportsDir.path}/$fileName');
      final bytes = excelFile.encode();
      if (bytes != null) {
        await file.writeAsBytes(bytes);
        if (mounted) {
          await Share.shareXFiles([XFile(file.path)], text: 'UUDS Aero DWC - $_reportTitle');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Builds a plain-text email draft (subject + body) from the currently
  /// filtered tagged data and opens it in the device's mail app (Outlook,
  /// Gmail, etc. — whichever the user selects/has set as default).
  Future<void> _sendEmail() async {
    final tagged = _taggedPhotos;
    if (tagged.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No tagged data to email for the current filter.')),
      );
      return;
    }

    setState(() => _emailing = true);
    try {
      final aircraftSet = tagged.map((p) => p.aircraftReg).toSet();
      final typeSet = tagged.map((p) => p.inspectionType).toSet();
      final dateFmt = DateFormat('dd-MMM-yyyy');

      String dateLabel;
      if (_range == null) {
        dateLabel = dateFmt.format(DateTime.now());
      } else if (_range!.start.year == _range!.end.year &&
          _range!.start.month == _range!.end.month &&
          _range!.start.day == _range!.end.day) {
        dateLabel = dateFmt.format(_range!.start);
      } else {
        dateLabel = '${dateFmt.format(_range!.start)} to ${dateFmt.format(_range!.end)}';
      }

      String subject;
      if (aircraftSet.length == 1 && typeSet.length == 1) {
        final verb = typeSet.first == 'Receiving' ? 'RECEIVED' : 'DESPATCHED';
        subject = '$verb AIRCRAFT PARTS FOR ${aircraftSet.first}  $dateLabel';
      } else {
        subject = 'UUDS AIRCRAFT PARTS REPORT  $dateLabel';
      }

      String pad(String s, int len) => s.length >= len ? '${s.substring(0, len - 1)} ' : s.padRight(len);

      final buffer = StringBuffer();
      buffer.writeln('Dear Team,');
      buffer.writeln();
      buffer.writeln(
        'Please find below the list of aircraft parts recorded${_selectedInspector != null ? ' by $_selectedInspector' : ''} ($dateLabel).',
      );
      buffer.writeln();
      buffer.writeln('${pad('DATE', 12)}${pad('A/C', 9)}${pad('PART NO', 14)}${pad('DESCRIPTION', 20)}${pad('LOCATION', 12)}${pad('QTY', 6)}UNIT');
      buffer.writeln('-' * 85);
      for (final p in tagged) {
        final d = DateFormat('dd-MMM-yyyy').format(DateTime.parse(p.timestamp));
        final loc = p.tagLocation.isNotEmpty ? p.tagLocation : p.partLocation;
        buffer.writeln(
          '${pad(d, 12)}${pad(p.aircraftReg, 9)}${pad(p.tagPartNo, 14)}${pad(p.tagDescription, 20)}${pad(loc, 12)}${pad(p.tagQty, 6)}EA',
        );
      }
      buffer.writeln();
      buffer.writeln('Regards,');
      buffer.writeln(_selectedInspector ?? 'UUDS Aero DWC');
      buffer.writeln('UUDS Aero DWC');

      final uri = Uri(
        scheme: 'mailto',
        query: 'subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(buffer.toString())}',
      );

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No email app found on this device.')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not create email: $e')));
    } finally {
      if (mounted) setState(() => _emailing = false);
    }
  }

  Widget _topButton(String label, bool selected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 46,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? kPrimary : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? kPrimary : Colors.black12),
            boxShadow: selected ? [BoxShadow(color: kPrimary.withOpacity(0.35), blurRadius: 6, offset: const Offset(0, 3))] : [],
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? Colors.white : Colors.black87,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final headers = _headers;
    final widths = _columnWidths;
    final rows = _rows;
    final totalWidth = widths.fold<double>(0, (a, b) => a + b);

    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      bottomNavigationBar: const AppBottomNav(current: AppTab.reports),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Column(
                children: [
                  Row(
                    children: [
                      _topButton('Tags Report', _kind == ReportKind.tagsReport, () => setState(() => _kind = ReportKind.tagsReport)),
                      _topButton('Aircraft Summary', _kind == ReportKind.aircraftSummary, () => setState(() => _kind = ReportKind.aircraftSummary)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _topButton('Part Location', _kind == ReportKind.partLocation, () => setState(() => _kind = ReportKind.partLocation)),
                      _topButton(
                        _inspectorButtonLabel(),
                        _selectedInspector != null,
                        _pickInspector,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.date_range, size: 18),
                      label: Text(
                        _range == null
                            ? 'Filter by Date (optional)'
                            : '${DateFormat('dd MMM').format(_range!.start)} - ${DateFormat('dd MMM yyyy').format(_range!.end)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                      onPressed: _pickRange,
                    ),
                  ),
                  if (_range != null)
                    IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        setState(() => _range = null);
                        _load();
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : rows.isEmpty
                      ? const Center(child: Text('No tagged parts found for this selection.', style: TextStyle(color: Colors.black45)))
                      : Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: totalWidth,
                              child: Column(
                                children: [
                                  // Frozen header row
                                  Container(
                                    color: kPrimary.withOpacity(0.10),
                                    child: Row(
                                      children: [
                                        for (int c = 0; c < headers.length; c++)
                                          Container(
                                            width: widths[c],
                                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                                            child: Text(
                                              headers[c],
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const Divider(height: 1),
                                  Expanded(
                                    child: ListView.builder(
                                      itemCount: rows.length,
                                      itemBuilder: (ctx, r) {
                                        final row = rows[r];
                                        return Container(
                                          color: r.isEven ? Colors.white : Colors.black.withOpacity(0.02),
                                          child: Row(
                                            children: [
                                              for (int c = 0; c < row.length; c++)
                                                Container(
                                                  width: widths[c],
                                                  padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
                                                  child: Text(row[c], style: const TextStyle(fontSize: 12)),
                                                ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: (_exporting || _emailing)
                  ? const Center(child: CircularProgressIndicator())
                  : Row(
                      children: [
                        Expanded(
                          child: PressableButton(
                            icon: Icons.grid_on_rounded,
                            label: 'Export Excel',
                            color: kAccent,
                            height: 56,
                            fontSize: 14,
                            onPressed: rows.isEmpty ? () {} : _exportExcel,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: PressableButton(
                            icon: Icons.email_rounded,
                            label: 'Send Email',
                            color: kPrimary,
                            height: 56,
                            fontSize: 14,
                            onPressed: rows.isEmpty ? () {} : _sendEmail,
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
