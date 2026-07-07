import 'package:flutter/material.dart';
import '../utils/theme.dart';

/// A big button with a 3D raised look and a satisfying press-down animation.
class PressableButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color color;
  final double height;
  final double fontSize;
  final bool enabled;

  const PressableButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color = kPrimary,
    this.height = 64,
    this.fontSize = 18,
    this.enabled = true,
  });

  @override
  State<PressableButton> createState() => _PressableButtonState();
}

class _PressableButtonState extends State<PressableButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = widget.enabled ? widget.color : Colors.grey;
    return GestureDetector(
      onTapDown: widget.enabled ? (_) => setState(() => _pressed = true) : null,
      onTapCancel: widget.enabled ? () => setState(() => _pressed = false) : null,
      onTapUp: widget.enabled ? (_) => setState(() => _pressed = false) : null,
      onTap: widget.enabled ? widget.onPressed : null,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: widget.height,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                effectiveColor,
                Color.lerp(effectiveColor, Colors.black, 0.18)!,
              ],
            ),
            boxShadow: (_pressed || !widget.enabled)
                ? []
                : [
                    BoxShadow(
                      color: effectiveColor.withOpacity(0.45),
                      offset: const Offset(0, 5),
                      blurRadius: 10,
                    ),
                  ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, color: Colors.white, size: widget.fontSize + 6),
              const SizedBox(width: 10),
              Text(
                widget.label,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: widget.fontSize,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
