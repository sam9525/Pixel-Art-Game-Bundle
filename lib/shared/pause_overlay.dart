import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/palette.dart';

/// Fast, utilitarian "PAUSED" overlay for Flame games.
///
/// Designed as a quick modal interruption — not cinematic like the start
/// overlay. Features a hard-blink title, tap-anywhere resume, keyboard
/// support, and minimal animation (150ms entrance).
class PauseOverlay extends StatefulWidget {
  const PauseOverlay({
    super.key,
    required this.onResume,
    required this.onQuit,
  });

  final VoidCallback onResume;
  final VoidCallback onQuit;

  @override
  State<PauseOverlay> createState() => _PauseOverlayState();
}

class _PauseOverlayState extends State<PauseOverlay>
    with TickerProviderStateMixin {
  // C1: Entrance fade + slide (one-shot, 150ms)
  late final AnimationController _overlayController;
  late final CurvedAnimation _overlayCurve;

  // C2: "PAUSED" hard blink (loops after entrance)
  late final AnimationController _blinkController;

  // C3: Button press feedback (one-shot, 100ms)
  late final AnimationController _feedbackController;

  late final FocusNode _focusNode;
  bool _actionTaken = false;
  VoidCallback? _pendingAction;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();

    // C1: Entrance
    _overlayController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _overlayCurve = CurvedAnimation(
      parent: _overlayController,
      curve: Curves.easeOutCubic,
    );

    // C2: Hard blink (starts after entrance)
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    // C3: Button feedback
    _feedbackController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _feedbackController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _pendingAction?.call();
      }
    });

    // Play entrance, then start blink loop
    _overlayController.forward();
    _overlayController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _blinkController.repeat(reverse: true);
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _feedbackController.dispose();
    _blinkController.dispose();
    _overlayCurve.dispose();
    _overlayController.dispose();
    super.dispose();
  }

  void _handleResume() {
    if (_actionTaken) return;
    _actionTaken = true;
    widget.onResume();
  }

  void _handleButtonTap(VoidCallback action) {
    if (_actionTaken) return;
    _actionTaken = true;
    _pendingAction = action;
    _feedbackController.forward(from: 0.0);
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.space ||
        event.logicalKey == LogicalKeyboardKey.enter) {
      _handleResume();
    } else if (event.logicalKey == LogicalKeyboardKey.keyQ) {
      if (!_actionTaken) {
        _actionTaken = true;
        widget.onQuit();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: GestureDetector(
        onTap: _handleResume,
        behavior: HitTestBehavior.translucent,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final shortSide = constraints.maxWidth < constraints.maxHeight
                ? constraints.maxWidth
                : constraints.maxHeight;
            final titleSize = (shortSide * 0.055).clamp(14.0, 30.0);
            final bodySize = (shortSide * 0.028).clamp(8.0, 14.0);
            final hintSize = (shortSide * 0.018).clamp(6.0, 10.0);
            final buttonPadH = (shortSide * 0.06).clamp(14.0, 36.0);
            final buttonPadV = (shortSide * 0.02).clamp(8.0, 16.0);
            final spacing = (shortSide * 0.03).clamp(8.0, 24.0);

            return FadeTransition(
              opacity: _overlayCurve,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -0.05),
                  end: Offset.zero,
                ).animate(_overlayCurve),
                child: Stack(
                  children: [
                    // Layer 0: Backdrop
                    Container(
                      color: Pico8Palette.black.withValues(alpha: 0.70),
                    ),

                    // Layer 1: CRT scanlines (full screen)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: const _CrtScanlinePainter(),
                        ),
                      ),
                    ),

                    // Layer 2: Content
                    Positioned.fill(
                      child: Align(
                        alignment: const Alignment(0, -0.15),
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth: constraints.maxWidth * 0.75,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // "PAUSED" title with hard blink
                              AnimatedBuilder(
                                animation: _blinkController,
                                builder: (context, child) {
                                  final on = _blinkController.value < 0.5;
                                  return Opacity(
                                    opacity: on ? 1.0 : 0.3,
                                    child: child,
                                  );
                                },
                                child: Text(
                                  'PAUSED',
                                  style: TextStyle(
                                    fontFamily: 'PressStart2P',
                                    fontSize: titleSize,
                                    color: Pico8Palette.lavender,
                                  ),
                                ),
                              ),
                              SizedBox(height: spacing),

                              // Small divider (3 dots)
                              _PixelDivider(color: Pico8Palette.lavender),
                              SizedBox(height: spacing * 1.5),

                              // RESUME button
                              _PauseButton(
                                label: 'RESUME',
                                borderColor: Pico8Palette.green,
                                textColor: Pico8Palette.green,
                                fontSize: bodySize,
                                paddingH: buttonPadH,
                                paddingV: buttonPadV,
                                feedbackAnimation: _feedbackController,
                                onTap: () =>
                                    _handleButtonTap(widget.onResume),
                              ),
                              SizedBox(height: spacing * 0.6),

                              // QUIT button
                              _PauseButton(
                                label: 'QUIT',
                                borderColor: Pico8Palette.darkGrey,
                                textColor: Pico8Palette.lightGrey,
                                fontSize: bodySize,
                                paddingH: buttonPadH,
                                paddingV: buttonPadV,
                                feedbackAnimation: _feedbackController,
                                onTap: () =>
                                    _handleButtonTap(widget.onQuit),
                              ),
                              SizedBox(height: spacing * 1.2),

                              // Hint text
                              Text(
                                'TAP ANYWHERE TO RESUME',
                                style: TextStyle(
                                  fontFamily: 'PressStart2P',
                                  fontSize: hintSize,
                                  color: Pico8Palette.darkGrey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Minimal 3-dot pixel divider.
class _PixelDivider extends StatelessWidget {
  const _PixelDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < 3; i++) ...[
          Container(
            width: 4,
            height: 4,
            color: i == 1 ? color : color.withValues(alpha: 0.4),
          ),
          if (i < 2) const SizedBox(width: 4),
        ],
      ],
    );
  }
}

/// Sharp-edged arcade button with press feedback.
class _PauseButton extends StatefulWidget {
  const _PauseButton({
    required this.label,
    required this.borderColor,
    required this.textColor,
    required this.fontSize,
    required this.paddingH,
    required this.paddingV,
    required this.feedbackAnimation,
    required this.onTap,
  });

  final String label;
  final Color borderColor;
  final Color textColor;
  final double fontSize;
  final double paddingH;
  final double paddingV;
  final Animation<double> feedbackAnimation;
  final VoidCallback onTap;

  @override
  State<_PauseButton> createState() => _PauseButtonState();
}

class _PauseButtonState extends State<_PauseButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      behavior: HitTestBehavior.opaque,
      child: Container(
        constraints: const BoxConstraints(minWidth: 120, minHeight: 44),
        padding: EdgeInsets.symmetric(
          horizontal: widget.paddingH,
          vertical: widget.paddingV,
        ),
        decoration: BoxDecoration(
          color: _pressed
              ? widget.borderColor.withValues(alpha: 0.25)
              : Pico8Palette.darkBlue,
          border: Border.all(
            color: widget.borderColor,
            width: _pressed ? 3 : 2,
          ),
        ),
        child: Center(
          child: Text(
            widget.label,
            style: TextStyle(
              fontFamily: 'PressStart2P',
              fontSize: widget.fontSize,
              color: widget.textColor,
            ),
          ),
        ),
      ),
    );
  }
}

/// Semi-transparent horizontal scanlines for CRT effect.
class _CrtScanlinePainter extends CustomPainter {
  const _CrtScanlinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Pico8Palette.black.withValues(alpha: 0.10);
    const lineHeight = 2.0;
    const gap = 2.0;

    for (double y = 0; y < size.height; y += lineHeight + gap) {
      canvas.drawRect(
        Rect.fromLTWH(0, y, size.width, lineHeight),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
