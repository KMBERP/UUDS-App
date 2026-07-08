import 'package:flutter/material.dart';

class InspectionTypeCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData? icon;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  const InspectionTypeCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon,
    required this.color,
    required this.onTap,
    this.enabled = true,
  });

  @override
  State<InspectionTypeCard> createState() => _InspectionTypeCardState();
}

class _InspectionTypeCardState extends State<InspectionTypeCard> with SingleTickerProviderStateMixin {
  bool _pressed = false;
  late final AnimationController _borderController;

  @override
  void initState() {
    super.initState();
    _borderController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _borderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.enabled ? widget.color : Colors.grey.shade400;
    return GestureDetector(
      onTapDown: widget.enabled ? (_) => setState(() => _pressed = true) : null,
      onTapCancel: widget.enabled ? () => setState(() => _pressed = false) : null,
      onTapUp: widget.enabled ? (_) => setState(() => _pressed = false) : null,
      onTap: widget.enabled ? widget.onTap : null,
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: AnimatedBuilder(
          animation: _borderController,
          builder: (context, child) {
            final borderOpacity = widget.enabled ? (0.3 + 0.7 * _borderController.value) : 0.15;
            return Container(
              height: 130,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(borderOpacity), width: 2),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [color, Color.lerp(color, Colors.black, 0.28)!],
                ),
                boxShadow: (_pressed || !widget.enabled)
                    ? []
                    : [BoxShadow(color: color.withOpacity(0.5), offset: const Offset(0, 5), blurRadius: 10)],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.icon != null)
                    Icon(widget.icon, color: Colors.white.withOpacity(0.95), size: 28),
                  if (widget.icon != null) const SizedBox(height: 6),
                  Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    widget.subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 11),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
