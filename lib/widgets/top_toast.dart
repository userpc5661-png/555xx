import 'package:flutter/material.dart';

enum TopToastKind { success, warning, error }

/// A small notice at the top of the screen. It ignores touches, so it never
/// blocks a button, and it disappears on its own. Shown on the root overlay,
/// so it stays visible after the current screen is closed.
class TopToast {
  TopToast._();

  static OverlayEntry? _current;

  static void show(
    BuildContext context,
    String message, {
    TopToastKind kind = TopToastKind.success,
    Duration? duration,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _current?.remove();
    _current = null;

    final (color, icon) = switch (kind) {
      TopToastKind.success => (Colors.green.shade700, Icons.verified_rounded),
      TopToastKind.warning => (Colors.orange.shade800, Icons.info_rounded),
      TopToastKind.error => (Colors.red.shade700, Icons.error_rounded),
    };

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _TopToastView(
        message: message,
        color: color,
        icon: icon,
        duration: duration ??
            (kind == TopToastKind.success
                ? const Duration(milliseconds: 2200)
                : const Duration(seconds: 5)),
        onDone: () {
          if (_current == entry) _current = null;
          if (entry.mounted) entry.remove();
        },
      ),
    );
    _current = entry;
    overlay.insert(entry);
  }
}

class _TopToastView extends StatefulWidget {
  final String message;
  final Color color;
  final IconData icon;
  final Duration duration;
  final VoidCallback onDone;

  const _TopToastView({
    required this.message,
    required this.color,
    required this.icon,
    required this.duration,
    required this.onDone,
  });

  @override
  State<_TopToastView> createState() => _TopToastViewState();
}

class _TopToastViewState extends State<_TopToastView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    await _controller.forward();
    await Future<void>.delayed(widget.duration);
    if (!mounted) return;
    await _controller.reverse();
    if (mounted) widget.onDone();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 16,
      right: 16,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: _controller,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.3),
              end: Offset.zero,
            ).animate(_controller),
            child: Material(
              color: widget.color,
              elevation: 6,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(widget.icon, color: Colors.white, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
