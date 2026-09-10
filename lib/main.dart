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
import 'package:shared_preferences/shared_preferences.dart';

// Brightness range (0..7 inclusive) => 8 stops on the dial.
const int kMinBrightness = 0;
const int kMaxBrightness = 7;

// The torch device path (requires root to write).
const String kTorchDevice =
    '/sys/devices/platform/flashlights_mt6360/torchbrightness';

// Candidates for the `su` binary, probed in order at runtime.
//
// On Android there is no /bin, so /bin/su never exists — the previous hard
// coded /bin/su failed with "No such file or directory" before root was ever
// attempted. /system/bin/su is the standard location (Magisk, KernelSU,
// APatch/FolkPatch hook execve of it via kernel "sucompat", which is how apps
// without direct /data/adb access reach root). The others cover alternative
// setups (e.g. /data/adb/ap/bin/su for APatch/FolkPatch when readable).
const List<String> kSuCandidates = <String>[
  '/system/bin/su',
  '/system/xbin/su',
  '/su/bin/su',
  '/data/adb/ap/bin/su',
  '/sbin/su',
  '/magisk/.core/bin/su',
];

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
  return kMinBrightness + (idx < 0 ? 0 : (idx > kStops - 1 ? kStops - 1 : idx));
}

/// Angle (radians) corresponding to the given brightness [value].
double angleForValue(int value) =>
    -math.pi / 2 + (value - kMinBrightness) * (2 * math.pi / kStops);

// --- Settings / icon chooser -------------------------------------------------

/// Preference key for the user's chosen launcher icon.
const String kPrefIcon = 'chosen_icon';

/// A selectable icon variant. Each variant provides a Flutter [IconData]
/// for use in-app and an Android resource name fallback.
class TorchIcon {
  const TorchIcon({
    required this.id,
    required this.iconData,
    required this.label,
    this.androidResName,
  });

  final String id;
  final IconData iconData;
  final String label;
  final String? androidResName;
}

/// Built-in icon variants the user can choose from. The default is the
/// classic torch (flash) icon; the others are thematic variants.
const List<TorchIcon> kTorchIcons = <TorchIcon>[
  TorchIcon(id: 'torch', iconData: Icons.flash_on, label: 'Torch'),
  TorchIcon(id: 'star', iconData: Icons.star, label: 'Star'),
  TorchIcon(id: 'moon', iconData: Icons.nightlight, label: 'Moon'),
  TorchIcon(id: 'sun', iconData: Icons.wb_sunny, label: 'Sun'),
];

/// Returns the icon variant currently selected by the user, defaulting to
/// the first entry (`torch`) when nothing has been persisted yet.
///
/// On Android, changing the launcher icon needs a manifest-level
/// `android:icon` change. This in-app choice is the source of truth that a
/// follow-up can use (for example by adding `android:icon`-backed aliases
/// in the manifest or by mirroring the selection in [TorchTileService]).
TorchIcon iconForId(String id) =>
    kTorchIcons.firstWhere((i) => i.id == id, orElse: () => kTorchIcons.first);

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
      routes: <String, WidgetBuilder>{
        '/settings': (BuildContext context) => const TorchSettingsPage(),
      },
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
  TorchIcon _icon = kTorchIcons.first;

  @override
  void initState() {
    super.initState();
    _loadIcon();
  }

  /// Loads the icon variant currently selected in settings, so the status
  /// area reflects the choice made in [TorchSettingsPage].
  Future<void> _loadIcon() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (!mounted) {
      return;
    }
    setState(() {
      _icon = iconForId(prefs.getString(kPrefIcon) ?? kTorchIcons.first.id);
    });
  }

  /// Writes the current brightness level to the torch device as root.
  ///
  /// Probes the known `su` locations and escalates with the first one that
  /// exists, then runs:
  ///
  ///     su -c 'echo "N" > /sys/devices/platform/flashlights_mt6360/torchbrightness'
  Future<void> _writeDevice() async {
    if (_busy) {
      return;
    }
    _busy = true;
    _status = null;
    setState(() {});
    try {
      final String command = 'echo "$_value" > "$kTorchDevice"';
      final String? suPath = await _resolveSuPath();
      if (suPath == null) {
        _root = false;
        _status = 'No su binary found — root not granted?';
      } else {
        final ProcessResult result = await Process.run(suPath, <String>[
          '-c',
          command,
        ], runInShell: false);
        if (result.exitCode == 0) {
          _root = true;
          _status = 'Brightness set to $_value';
        } else {
          _root = false;
          _status =
              'su exited ${result.exitCode} — root denied? ${result.stderr}';
        }
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

  /// Returns the first existing `su` binary path, or null if none is found.
  Future<String?> _resolveSuPath() async {
    for (final String candidate in kSuCandidates) {
      try {
        final ProcessResult check = await Process.run(candidate, const <String>[
          '--version',
        ], runInShell: false);
        if (check.exitCode != 127) {
          return candidate;
        }
      } on ProcessException {
        // Not present (or not executable) at this path — try the next one.
      }
    }
    return null;
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
      appBar: AppBar(
        title: const Text('BegoTorch'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).pushNamed('/settings').then((_) {
                // The user may have changed the icon in settings; reload it
                // when returning to the home screen.
                _loadIcon();
              });
            },
          ),
        ],
      ),
      body: Center(
        child: SizedBox(
          width: 320,
          height: 480,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Icon(
                _icon.iconData,
                key: const ValueKey<String>('home_icon'),
                size: 28,
                color: _kAccent,
              ),
              const SizedBox(height: 6),
              Text(_icon.label, style: theme.textTheme.titleLarge!),
              const SizedBox(height: 8),
              _buildStatusLine(theme),
              const SizedBox(height: 26),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: _handleTap,
                onPanUpdate: _handleDrag,
                child: CustomPaint(
                  key: const ValueKey<String>('torch_dial'),
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
  bool shouldRepaint(_DialPainter oldDelegate) => oldDelegate.value != value;

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
    canvas.drawCircle(
      center,
      36,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = _kHubBorder,
    );
  }
}

// --- Settings page with icon chooser ----------------------------------------

/// Settings screen offering an icon-chooser for the app launcher icon.
///
/// On Android the launcher icon is declared in AndroidManifest.xml and cannot
/// be changed at runtime by a non-root app.  What *can* change at runtime is:
///   - the Quick Settings tile icon (set in [TorchTileService])
///   - which icon asset the Flutter UI itself renders
///
/// This page persists the user's choice via SharedPreferences so both the
/// tile and the in-app display stay in sync.  The preference defaults to the
/// classic torch icon (`'torch'`).
class TorchSettingsPage extends StatefulWidget {
  const TorchSettingsPage({super.key});

  @override
  State<TorchSettingsPage> createState() => _TorchSettingsPageState();
}

class _TorchSettingsPageState extends State<TorchSettingsPage> {
  String _selectedId = kTorchIcons.first.id;

  @override
  void initState() {
    super.initState();
    _loadSelected();
  }

  Future<void> _loadSelected() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedId = prefs.getString(kPrefIcon) ?? kTorchIcons.first.id;
    });
  }

  Future<void> _select(String id) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPrefIcon, id);
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedId = id;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      backgroundColor: _kBackground,
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Text('Launcher Icon', style: theme.textTheme.titleMedium),
          ),
          _appDivider,
          RadioGroup<String>(
            groupValue: _selectedId,
            onChanged: (String? v) {
              if (v != null) {
                _select(v);
              }
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final TorchIcon icon in kTorchIcons)
                  RadioListTile<String>(
                    key: ValueKey<String>('icon_option_${icon.id}'),
                    value: icon.id,
                    activeColor: _kAccent,
                    secondary: Icon(icon.iconData, color: _kAccent),
                    title: Text(icon.label, style: theme.textTheme.bodyLarge),
                    subtitle: _selectedId == icon.id
                        ? Text(
                            'Selected',
                            style: theme.textTheme.bodySmall!.apply(
                              color: _kAccent,
                            ),
                          )
                        : null,
                    // Highlight the selected item's background for visual clarity.
                    selected: _selectedId == icon.id,
                    selectedTileColor: _kRing.withValues(alpha: 0.3),
                  ),
              ],
            ),
          ),
          _appDivider,
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Text('About', style: theme.textTheme.titleMedium),
          ),
          _appDivider,
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('App version'),
            subtitle: const Text('1.0.0+1'),
          ),
          ListTile(
            leading: const Icon(Icons.favorite),
            title: const Text('Icon source'),
            subtitle: const Text(
              'Arch Linux glyph — archlinux.org/art/ (trademark policy)',
            ),
          ),
        ],
      ),
    );
  }
}

/// A thin divider matching the app's muted palette, used inside ListViews
/// to group settings sections.
const Divider _appDivider = Divider(
  height: 1,
  thickness: 1,
  indent: 24,
  endIndent: 24,
  color: _kRing,
);
