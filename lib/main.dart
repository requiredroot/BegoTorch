// BegoTorch — a root-requiring torch brightness app for begonia.
//
// A modern, minimalistic circular slider with 8 stops (0..7) that controls the
// torch brightness by running, through the `su` binary:
//
//     echo "N" > /sys/devices/platform/flashlights_mt6360/torchbrightness
//
// Because writing to that device requires root, the app escalates privileges
// with `su`.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

// Brightness range (0..7 inclusive) => 8 stops on the dial.
const int kMinBrightness = 0;
const int kMaxBrightness = 7;

// The torch device path (requires root to write).
const String kTorchDevice =
    '/sys/devices/platform/flashlights_mt6360/torchbrightness';

// The `su` binary used to escalate privileges.
const String kSuBinary = '/bin/su';

// Visual palette (dark, minimalistic).
const Color _kBackground = Color(0xFF0D0F13);
const Color _kAccent = Color(0xFFF2C94C);
const Color _kMuted = Color(0xFF8A94A0);
const Color _kHub = Color(0xFF0A0C10);
const Color _kRing = Color(0xFF2A3038);
const Color _kDot = Color(0xFF5A6470);
const Color _kDanger = Color(0xFFFF8A8A);
const Color _kHubBorder = Color(0xFF3A4350);

// Size of the square dial widget.
const double kDialSize = 240.0;

// Number of stops on the dial (8).
const int kStops = kMaxBrightness - kMinBrightness + 1;

void main() {
  runApp(const BegoTorchApp());
}

/// Brightness value for the given pointer [angle] (radians, 0 at +x, increasing
/// clockwise as y is down). Ranges kMinBrightness..kMaxBrightness.
int valueAtAngle(double angle) {
  double a = (angle + math.pi / 2) % (2 * math.pi);
  if (a < 0) {
    a += 2 * math.pi;
  }
  final int idx = (a / (2 * math.pi) * (kStops - 1)).round();
  return kMinBrightness + (idx < 0
      ? 0
      : (idx > kStops - 1 ? kStops - 1 : idx));
}

/// Angle (radians) corresponding to the given brightness [value].
double angleForValue(int value) =>
    -math.pi / 2 + (value - kMinBrightness) * (2 * math.pi / kStops);

class BegoTorchApp extends StatelessWidget {
  const BegoTorchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BegoTorch',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _kAccent,
          brightness: Brightness.dark,
        ),
      ),
      themeMode: ThemeMode.dark,
      home: const TorchHomePage(),
    );
  }
}

class TorchHomePage extends StatefulWidget {
  const TorchHomePage({super.key});

  @override
  State<TorchHomePage> createState() => _TorchHomePageState();
}

class _TorchHomePageState extends State<TorchHomePage> {
  int _value = 2;
  bool _root = false;
  bool _busy = false;
  String? _status;

  /// Run: /bin/su -c 'echo "N" > /sys/devices/platform/flashlights_mt6360/torchbrightness'
  Future<void> _writeDevice() async {
    if (_busy) {
      return;
    }
    _busy = true;
    _status = null;
    setState(() {});
    try {
      final String command = 'echo "$_value" > "$kTorchDevice"';
      final ProcessResult result = await Process.run(
        kSuBinary,
        <String>['-c', command],
        runInShell: false,
      );
      if (result.exitCode == 0) {
        _root = true;
        _status = 'Brightness set to $_value';
      } else {
        _root = false;
        _status = 'Need root: su exited ${result.exitCode}';
      }
    } on ProcessException catch (e) {
      _root = false;
      _status = 'Failed to run su: ${e.message}';
    } catch (_) {
      _root = false;
      _status = 'Failed to control the torch';
    }
    _busy = false;
    setState(() {});
  }

  void _apply(Offset position) {
    final double cx = kDialSize / 2;
    final double cy = kDialSize / 2;
    final double angle = math.atan2(position.dy - cy, position.dx - cx);
    final int value = valueAtAngle(angle);
    if (value != _value) {
      _value = value;
      setState(() {});
      _writeDevice();
    }
  }

  void _handleTap(TapDownDetails details) {
    _apply(details.localPosition);
  }

  void _handleDrag(DragUpdateDetails details) {
    _apply(details.localPosition);
  }

  Widget _buildStatusLine(ThemeData theme) {
    final String label;
    final Color color;
    if (_busy) {
      label = 'Applying…';
      color = _kMuted;
    } else if (_status != null) {
      label = _status!;
      color = _root ? _kAccent : _kDanger;
    } else {
      label = _root ? 'Root · ready' : 'Waiting for input';
      color = _root ? _kAccent : _kMuted;
    }
    return Text(label, style: theme.textTheme.bodyMedium!.apply(color: color));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      backgroundColor: _kBackground,
      appBar: AppBar(title: const Text('BegoTorch')),
      body: Center(
        child: SizedBox(
          width: 320,
          height: 480,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Text('Torch', style: theme.textTheme.titleLarge!),
              const SizedBox(height: 8),
              _buildStatusLine(theme),
              const SizedBox(height: 26),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: _handleTap,
                onPanUpdate: _handleDrag,
                child: CustomPaint(
                  size: const Size(kDialSize, kDialSize),
                  painter: _DialPainter(value: _value),
                ),
              ),
              const SizedBox(height: 18),
              Text('$_value', style: theme.textTheme.displayMedium!),
              const SizedBox(height: 10),
              Text(
                'Drag the ring · $kMinBrightness – $kMaxBrightness',
                style: theme.textTheme.bodyMedium!.apply(color: _kMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Custom painter drawing the round slider ring, stops and hub.
class _DialPainter extends CustomPainter {
  final int value;

  const _DialPainter({required this.value});

  @override
  bool shouldRepaint(_DialPainter oldDelegate) =>
      oldDelegate.value != value;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double ringR = (size.shortestSide / 2) - 6;

    // Stop dots evenly spaced around the ring; highlight the active one.
    for (int i = 0; i < kStops; i++) {
      final double a = angleForValue(kMinBrightness + i);
      final Offset p = Offset(
        center.dx + ringR * math.cos(a),
        center.dy + ringR * math.sin(a),
      );
      final bool active = i == value - kMinBrightness;
      canvas.drawCircle(p, 6, Paint()..color = active ? _kAccent : _kDot);
      if (active) {
        canvas.drawCircle(p, 3, Paint()..color = const Color(0xFFFFDF8A));
      }
    }

    // Full ring track.
    final Rect circle = Rect.fromCircle(center: center, radius: ringR);
    canvas.drawArc(
      circle,
      0,
      2 * math.pi,
      true,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..color = _kRing,
    );

    // Filled sector showing current brightness level.
    final double start = -math.pi / 2;
    final double end = angleForValue(value);
    final double sweep = end - start;
    if (sweep > 0.001) {
      canvas.drawArc(
        circle,
        start,
        sweep,
        true,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 14
          ..color = _kAccent,
      );
    }

    // Hub.
    canvas.drawCircle(center, 36, Paint()..color = _kHub);
    canvas.drawCircle(center, 36, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = _kHubBorder);
  }
}
