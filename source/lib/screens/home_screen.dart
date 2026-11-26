import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../db/db_helper.dart';
import '../models/models.dart';
import '../utils/backup_util.dart';
import '../utils/build_info.dart';
import '../utils/page_transitions.dart';
import '../utils/session.dart';
import '../utils/storage_paths.dart';
import '../utils/theme.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/inspection_type_card.dart';
import '../widgets/version_control_dialog.dart';
import 'aircraft_screen.dart';
import 'employee_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, int> _stats = {
    'aircraft': 0,
    'totalPhotos': 0,
    'todayPhotos': 0,
    'todayReceiving': 0,
    'todayDispatch': 0,
  };

  final TextEditingController _idController = TextEditingController();
  Employee? _matchedEmployee;
  bool _searched = false;
  List<Employee> _suggestions = [];

  DateTime? _lastBackPress;

  @override
  void initState() {
    super.initState();
    _loadStats();
    if (Session.currentEmployee != null) {
      // Switching back to the Home tab: the inspector is still "logged in"
      // in Session, so restore it immediately (no DB round-trip, no flash
      // of an empty/unselected state).
      _matchedEmployee = Session.currentEmployee;
      _searched = true;
      _idController.text = _matchedEmployee!.idNumber;
    } else {
      // Fresh app launch (process was fully killed): fall back to whatever
      // inspector was last saved to the database.
      _restoreLastEmployee();
    }
  }

  Future<void> _restoreLastEmployee() async {
    final savedId = await DBHelper.instance.getSetting(Session.lastEmployeeIdKey);
    if (savedId == null || savedId.isEmpty) return;

    // This only runs on a cold start (Session.currentEmployee is null,
    // meaning the app process itself is fresh - either first launch, or
    // Android killed the previous process while it was backgrounded). A
    // fresh process can't tell from memory alone how long it's actually
    // been, so check the last-activity timestamp InactivityGuard persists
    // to disk: if it's older than the timeout, this saved session should
    // already have been logged out - just finish the job now instead of
    // silently restoring someone's session an hour (or more) later.
    final lastActivityIso = await DBHelper.instance.getSetting(Session.lastActivityKey);
    if (lastActivityIso != null && lastActivityIso.isNotEmpty) {
      final lastActivity = DateTime.tryParse(lastActivityIso);
      if (lastActivity != null && DateTime.now().difference(lastActivity) >= Session.inactivityTimeout) {
        await DBHelper.instance.setSetting(Session.lastEmployeeIdKey, '');
        return;
      }
    }

    final emp = await DBHelper.instance.getEmployeeByIdInput(savedId);
    if (!mounted || emp == null) return;
    Session.login(emp);
    setState(() {
      _matchedEmployee = emp;
      _searched = true;
      _idController.text = emp.idNumber;
    });
  }

  @override
  void dispose() {
    _idController.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    final s = await DBHelper.instance.getStats();
    final backups = await BackupUtil.findAvailableBackups();
    // Silently remove redundant duplicate files from private storage to free up memory
    StoragePaths.cleanDuplicateStorageCopies();
    if (mounted) {
      setState(() {
        _stats = s;
        _availableBackups = backups;
      });
    }
  }

  List<File> _availableBackups = [];

  Future<void> _showRestoreDialog() async {
    final backups = await BackupUtil.findAvailableBackups();
    if (!mounted) return;
    final pathController = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.settings_backup_restore_rounded, color: kPrimary),
            SizedBox(width: 8),
            Text('Restore from Backup', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select a backup file to restore all your aircraft, photos, and tag records:',
                  style: TextStyle(fontSize: 13, color: Colors.black87),
                ),
                const SizedBox(height: 12),
                if (backups.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.withOpacity(0.3)),
                    ),
                    child: const Text(
                      'No backup zip files found automatically in Downloads or Pictures. You can enter the full file path below.',
                      style: TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                  )
                else
                  ...backups.map((f) {
                    final name = p.basename(f.path);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.archive_rounded, color: kPrimary),
                        title: Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: FutureBuilder<Map<String, dynamic>?>(
                          future: BackupUtil.getBackupVersionInfo(f),
                          builder: (ctx, snap) {
                            if (snap.hasData && snap.data != null) {
                              final m = snap.data!;
                              return Text('Version: v${m['appVersion'] ?? '1.8'} · DB v${m['dbVersion'] ?? '10'} · ${m['aircraftCount'] ?? 0} Aircraft', style: const TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.w500));
                            }
                            return Text(f.path, style: const TextStyle(fontSize: 10, color: Colors.black54));
                          },
                        ),
                        trailing: const Icon(Icons.download_rounded, color: Colors.green),
                        onTap: () async {
                          Navigator.pop(ctx);
                          await _executeRestore(f);
                        },
                      ),
                    );
                  }),
                const SizedBox(height: 14),
                const Text('Or enter custom backup path:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: pathController,
                  decoration: const InputDecoration(
                    hintText: '/storage/emulated/0/Download/UUDS_Backup.zip',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final customPath = pathController.text.trim();
              if (customPath.isNotEmpty && File(customPath).existsSync()) {
                Navigator.pop(ctx);
                await _executeRestore(File(customPath));
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('File not found at that path.')),
                );
              }
            },
            child: const Text('Restore File'),
          ),
        ],
      ),
    );
  }

  Future<void> _executeRestore(File file) async {
    final ok = await BackupUtil.restoreFromZip(file);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(backgroundColor: Colors.green, content: Text('Backup restored successfully! All data loaded.')),
      );
      _loadStats();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(backgroundColor: Colors.red, content: Text('Failed to restore backup file.')),
      );
    }
  }

  Widget _restoreBanner(File backupFile) {
    final fileName = p.basename(backupFile.path);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF3B82F6), width: 1.2),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.settings_backup_restore_rounded, color: Color(0xFF1D4ED8), size: 22),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Found Existing Backup',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E3A8A)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Backup file: $fileName\nTap Restore to reload all previous aircraft, photos, and tag records.',
            style: const TextStyle(fontSize: 12, color: Colors.black87),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1D4ED8)),
                icon: const Icon(Icons.download_done_rounded, size: 18),
                label: const Text('Restore Data Now'),
                onPressed: () => _executeRestore(backupFile),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _onIdChanged(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _matchedEmployee = null;
        _searched = false;
        _suggestions = [];
      });
      return;
    }
    final emp = await DBHelper.instance.getEmployeeByIdInput(trimmed);
    final suggestions = await DBHelper.instance.getEmployeesByIdPrefix(trimmed);
    if (!mounted) return;
    setState(() {
      _matchedEmployee = emp;
      _searched = true;
      // Don't bother showing a suggestions list of just the one exact match.
      _suggestions = (emp != null && suggestions.length <= 1) ? [] : suggestions;
    });
    if (emp != null) {
      // ID matched - auto-dismiss the keyboard.
      FocusManager.instance.primaryFocus?.unfocus();
      Session.login(emp);
      DBHelper.instance.setSetting(Session.lastEmployeeIdKey, emp.idNumber);
    }
  }

  void _selectSuggestion(Employee e) {
    setState(() {
      _matchedEmployee = e;
      _searched = true;
      _suggestions = [];
      _idController.text = e.idNumber;
    });
    FocusManager.instance.primaryFocus?.unfocus();
    Session.login(e);
    DBHelper.instance.setSetting(Session.lastEmployeeIdKey, e.idNumber);
  }

  Future<void> _pickFromList() async {
    final employees = await DBHelper.instance.getEmployees();
    if (!mounted) return;
    final chosen = await showDialog<Employee>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Select Inspector'),
        children: employees
            .map((e) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, e),
                  child: Text(e.idNumber.isEmpty ? e.name : '${e.name} (UUDS-${e.idNumber})'),
                ))
            .toList(),
      ),
    );
    if (chosen != null) {
      setState(() {
        _matchedEmployee = chosen;
        _searched = true;
        _idController.text = chosen.idNumber;
      });
      Session.login(chosen);
      DBHelper.instance.setSetting(Session.lastEmployeeIdKey, chosen.idNumber);
    }
  }

  void _startInspection(InspectionType type) {
    if (_matchedEmployee == null) return;
    Navigator.of(context).push(
      fadeSlideRoute(AircraftScreen(employee: _matchedEmployee!, type: type)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final now = DateTime.now();
        if (_lastBackPress == null || now.difference(_lastBackPress!) > const Duration(seconds: 2)) {
          _lastBackPress = now;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Press back again to logout'), duration: Duration(seconds: 2)),
          );
        } else {
          Session.logout();
          DBHelper.instance.setSetting(Session.lastEmployeeIdKey, '');
          setState(() {
            _matchedEmployee = null;
            _searched = false;
            _idController.clear();
          });
          _lastBackPress = null;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Logged out')),
          );
          // Close the app after logout
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
      backgroundColor: Colors.black,
      bottomNavigationBar: const AppBottomNav(current: AppTab.home),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // New custom Emirates DXB Workshop background
          Image.asset(
            'assets/branding/home_background.jpg',
            fit: BoxFit.cover,
            alignment: Alignment.center,
          ),
          // Balanced gradient overlay protecting text readability while showcasing vibrant hangar colors
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.50),
                  Colors.black.withOpacity(0.06),
                  Colors.black.withOpacity(0.68),
                ],
                stops: const [0.0, 0.40, 1.0],
              ),
            ),
          ),
          SafeArea(
            child: RefreshIndicator(
              onRefresh: _loadStats,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
                children: [
                  const Text(
                    'WELCOME TO',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12.5,
                      letterSpacing: 2.5,
                      fontWeight: FontWeight.w700,
                      shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                    ),
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    'UUDS PARTS INSPECTION',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                      shadows: [Shadow(color: Colors.black87, blurRadius: 6)],
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Aviation Maintenance Quality Assurance',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => VersionControlDialog.show(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white38, width: 0.8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.verified_user_outlined, size: 12, color: Colors.white70),
                            const SizedBox(width: 5),
                            Text(
                              'Build: $kBuildId · Version Control',
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontFamily: 'monospace', fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: _showRestoreDialog,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1D4ED8).withOpacity(0.85),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white30, width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.settings_backup_restore_rounded, size: 14, color: Colors.white),
                            SizedBox(width: 6),
                            Text(
                              'Restore Data from Backup',
                              style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_availableBackups.isNotEmpty && (_stats['aircraft'] ?? 0) == 0)
                    _restoreBanner(_availableBackups.first),
                  _statsCard(),
                  const SizedBox(height: 16),
                  _inspectorCard(),
                  const SizedBox(height: 16),
                  _inspectionTypeSection(),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _statsCard() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          const Text("TODAY'S ACTIVITY", style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, letterSpacing: 1, color: Color(0xFF2E7D32))),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _statItem(Icons.flight, kPrimary, 'Aircraft', '${_stats['aircraft']}')),
              _divider(),
              Expanded(child: _statItem(Icons.download_rounded, kPrimary, 'Receiving', '${_stats['todayReceiving']}')),
              _divider(),
              Expanded(child: _statItem(Icons.upload_rounded, kDispatch, 'Dispatching', '${_stats['todayDispatch']}')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(width: 1, height: 40, color: Colors.black12);

  Widget _statItem(IconData icon, Color color, String label, String value) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
      ],
    );
  }

  Widget _inspectorCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text('Select Inspector', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: kHeaderBlue)),
          const SizedBox(height: 10),
          Container(
            width: 220,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Text('UUDS-', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Expanded(
                  child: TextField(
                    controller: _idController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16),
                    decoration: const InputDecoration(border: InputBorder.none, hintText: 'e.g. 476', isDense: true),
                    onChanged: _onIdChanged,
                  ),
                ),
                if (_searched)
                  Icon(
                    _matchedEmployee != null ? Icons.check_circle : Icons.cancel,
                    color: _matchedEmployee != null ? Colors.green : Colors.red,
                  ),
              ],
            ),
          ),
          if (_suggestions.isNotEmpty)
            Container(
              width: 220,
              margin: const EdgeInsets.only(top: 4),
              constraints: const BoxConstraints(maxHeight: 176),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.black12),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 6, offset: const Offset(0, 2))],
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _suggestions.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final e = _suggestions[i];
                  return ListTile(
                    dense: true,
                    visualDensity: const VisualDensity(vertical: -2),
                    title: Text('UUDS-${e.idNumber}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                    subtitle: Text(e.name, style: const TextStyle(fontSize: 12)),
                    onTap: () => _selectSuggestion(e),
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
          if (_matchedEmployee != null)
            Text(_matchedEmployee!.name, textAlign: TextAlign.center, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w700, fontSize: 15))
          else if (_searched && _suggestions.isEmpty)
            const Text('ID not found', textAlign: TextAlign.center, style: TextStyle(color: Colors.red, fontSize: 13)),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: _pickFromList,
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: const Size(0, 32)),
                child: const Text('Select from list instead', style: TextStyle(fontSize: 12.5)),
              ),
              const SizedBox(width: 4),
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(fadeSlideRoute(const EmployeeScreen()));
                },
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: const Size(0, 32)),
                child: const Text('Manage inspectors list', style: TextStyle(fontSize: 12.5, color: Colors.black54)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _inspectionTypeSection() {
    final enabled = _matchedEmployee != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.94),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 3))],
            ),
            child: const Text(
              'Select Inspection Type',
              textAlign: TextAlign.center,
              style: TextStyle(color: kHeaderBlue, fontWeight: FontWeight.w700, fontSize: 17),
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: InspectionTypeCard(
                title: 'RECEIVING PARTS',
                subtitle: 'Record & inspect incoming Aircraft Parts',
                color: kPrimary,
                enabled: enabled,
                icon: Icons.download_rounded,
                onTap: () => _startInspection(InspectionType.receiving),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InspectionTypeCard(
                title: 'DESPATCHING PARTS',
                subtitle: 'Verify & log outgoing Aircraft Parts',
                color: kDispatch,
                enabled: enabled,
                icon: Icons.upload_rounded,
                onTap: () => _startInspection(InspectionType.dispatch),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
