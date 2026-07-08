import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../db/db_helper.dart';
import '../models/models.dart';
import '../utils/page_transitions.dart';
import '../utils/theme.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/inspection_type_card.dart';
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

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  @override
  void dispose() {
    _idController.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    final s = await DBHelper.instance.getStats();
    if (mounted) setState(() => _stats = s);
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
      _suggestions = (emp != null && suggestions.length <= 1) ? [] : suggestions;
    });
    if (emp != null) {
      FocusManager.instance.primaryFocus?.unfocus();
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
    }
  }

  void _startInspection(InspectionType type) {
    if (_matchedEmployee == null) return;
    Navigator.of(context).push(
      fadeSlideRoute(AircraftScreen(employee: _matchedEmployee!, type: type)),
    );
  }

  Future<bool> _onWillPop() async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Exit App?'),
        content: const Text('Do you want to exit the app?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes, Exit')),
        ],
      ),
    );
    return shouldExit ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        bottomNavigationBar: const AppBottomNav(current: AppTab.home),
        body: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset('assets/branding/home_background.jpg', fit: BoxFit.cover),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.65),
                    Colors.black.withOpacity(0.25),
                    Colors.black.withOpacity(0.75),
                  ],
                  stops: const [0.0, 0.35, 1.0],
                ),
              ),
            ),
            SafeArea(
              child: RefreshIndicator(
                onRefresh: _loadStats,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
                  children: [
                    const Text(
                      'WELCOME TO',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: kHeaderBlue, fontSize: 13, letterSpacing: 2, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'UUDS PARTS INSPECTION',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: kHeaderBlue, fontSize: 22, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Streamline your inspections efficiently',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: kHeaderBlue, fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 20),
                    _statsCard(),
                    const SizedBox(height: 72),
                    _inspectorCard(),
                    const SizedBox(height: 72),
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
              Expanded(child: _statItem(Icons.call_received_rounded, kPrimary, 'Receiving', '${_stats['todayReceiving']}')),
              _divider(),
              Expanded(child: _statItem(Icons.call_made_rounded, kDispatch, 'Dispatching', '${_stats['todayDispatch']}')),
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
                icon: Icons.flight_land,
                color: kPrimary,
                enabled: enabled,
                onTap: () => _startInspection(InspectionType.receiving),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InspectionTypeCard(
                title: 'DESPATCHING PARTS',
                subtitle: 'Verify & log outgoing Aircraft Parts',
                icon: Icons.flight_takeoff,
                color: kDispatch,
                enabled: enabled,
                onTap: () => _startInspection(InspectionType.dispatch),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
