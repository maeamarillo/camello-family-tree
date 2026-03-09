import 'package:flutter/material.dart';

class PlusPort extends StatefulWidget {
  const PlusPort({
    super.key,
    required this.tooltip,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    this.onTap,
  });

  final String tooltip;
  final void Function(Offset globalPos) onStart;
  final void Function(Offset globalPos) onUpdate;
  final void Function(Offset globalPos) onEnd;
  final VoidCallback? onTap;

  @override
  State<PlusPort> createState() => _PlusPortState();
}

class _PlusPortState extends State<PlusPort> {
  static const double _dragStartThreshold = 6.0;

  Offset? _downGlobal;
  Offset? _lastGlobal;
  bool _started = false;

  void _reset() {
    _downGlobal = null;
    _lastGlobal = null;
    _started = false;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Tooltip(
        message: widget.tooltip,
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (e) {
            _downGlobal = e.position;
            _lastGlobal = e.position;
            _started = false;
          },
          onPointerMove: (e) {
            if (_downGlobal == null) return;
            _lastGlobal = e.position;

            final dist = (e.position - _downGlobal!).distance;

            if (!_started && dist >= _dragStartThreshold) {
              _started = true;
              widget.onStart(_downGlobal!);
            }

            if (_started) widget.onUpdate(e.position);
          },
          onPointerUp: (_) {
            if (_started) widget.onEnd(_lastGlobal ?? Offset.zero);
            _reset();
          },
          onPointerCancel: (_) {
            if (_started) widget.onEnd(_lastGlobal ?? Offset.zero);
            _reset();
          },
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFB9C0CC), width: 1),
              boxShadow: const [
                BoxShadow(
                  blurRadius: 6,
                  offset: Offset(0, 2),
                  color: Colors.black12,
                ),
              ],
            ),
            child: const Center(
              child: Icon(Icons.add, size: 14, color: Color(0xFF6E7685)),
            ),
          ),
        ),
      ),
    );
  }
}
