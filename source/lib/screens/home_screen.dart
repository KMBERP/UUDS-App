import 'package:flutter/material.dart';
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
      });
      return;
    }
    final emp = await DBHelper.instance.getEmployeeByIdInput(trimmed);
    if (!mounted) return;
    setState(() {
      _matchedEmployee = emp;
      _searched = true;
    });
    if (emp != null) {
      // ID matched - auto-dismiss the keyboard.
      FocusManager.instance.primaryFocus?.unfocus();
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                  const SizedBox(height: 18),
                  _inspectorCard(),
                  const SizedBox(height: 40),
                  _inspectionTypeSection(),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
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
          const Text("TODAY'S ACTIVITY", style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 1, color: Colors.black54)),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Select Inspector', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 10),
          Container(
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
          const SizedBox(height: 8),
          if (_matchedEmployee != null)
            Text(_matchedEmployee!.name, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w700, fontSize: 15))
          else if (_searched)
            const Text('ID not found', style: TextStyle(color: Colors.red, fontSize: 13)),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: _pickFromList,
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
                child: const Text('Select from list instead', style: TextStyle(fontSize: 12.5)),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(fadeSlideRoute(const EmployeeScreen()));
                },
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text('Select Inspection Type', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
        ),
        Row(
          children: [
            Expanded(
              child: InspectionTypeCard(
                title: 'RECEIVING PARTS',
                subtitle: 'Record & inspect incoming Aircraft Parts',
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
