import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'check_result.dart';
import 'local_engine_stub.dart' if (dart.library.ffi) 'local_engine.dart';
import 'ui.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const CwsbApp());
}

class CwsbApp extends StatelessWidget {
  const CwsbApp({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
          useMaterial3: true,
          brightness: b,
          colorScheme: ColorScheme.fromSeed(seedColor: leaf, brightness: b),
          scaffoldBackgroundColor: Palette(b == Brightness.dark).page,
        );
    return MaterialApp(
      title: 'CWSB Check',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: const HomePage(),
    );
  }
}

extension on CheckResult {
  Color get color => switch (label) { 'Healthy' => good, 'Unhealthy' => bad, _ => warn };
  IconData get icon => switch (label) {
        'Healthy' => Icons.verified_rounded,
        'Unhealthy' => Icons.bug_report_rounded,
        _ => Icons.help_rounded,
      };
}

class _ServerMessage implements Exception {
  _ServerMessage(this.message);
  final String message;
}

enum _ModelState { loading, ready, failed }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _prefKey = 'server_url', _modeKey = 'mode';
  final _picker = ImagePicker();
  final _engine = LocalEngine();
  final _scroll = ScrollController();

  String _server = '';
  bool _onDevice = localSupported; // run the model inside the app, or ask the model server
  _ModelState _model = _ModelState.loading;
  Uint8List? _image; // photo chosen or captured, waiting for Proceed
  CheckResult? _result;
  bool _busy = false;
  String _busyText = 'Checking the photo';
  int _view = 0; // 0 heatmap, 1 photo, 2 compare
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    var url = prefs.getString(_prefKey) ?? '';
    // In a browser the app is normally served by the model server itself.
    if (url.isEmpty && kIsWeb) url = Uri.base.origin;
    // In the Android emulator, 10.0.2.2 is the computer the emulator runs on.
    if (url.isEmpty && defaultTargetPlatform == TargetPlatform.android) url = 'http://10.0.2.2:8765';
    final onDevice = localSupported && (prefs.getString(_modeKey) ?? 'device') == 'device';
    if (!mounted) return;
    setState(() {
      _server = url;
      _onDevice = onDevice;
    });
    if (onDevice) _warmUp();
    if (!onDevice && url.isEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => _editSettings());
  }

  /// Loads the model in the background so the first check is fast.
  Future<void> _warmUp() async {
    setState(() => _model = _ModelState.loading);
    // Let the first screen draw before the model is opened.
    await Future<void>.delayed(const Duration(milliseconds: 450));
    try {
      await _engine.warmUp();
      if (mounted) setState(() => _model = _ModelState.ready);
    } catch (e) {
      // ignore: avoid_print
      print('CWSB_ERROR warm-up $e');
      if (mounted) setState(() => _model = _ModelState.failed);
    }
  }

  Future<void> _editSettings() async {
    final controller = TextEditingController(text: _server.isEmpty ? 'http://192.168.1.10:8765' : _server);
    var onDevice = _onDevice;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom + MediaQuery.paddingOf(ctx).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Where the model runs', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            if (localSupported) ...[
              SegmentSwitch(
                labels: const ['On this phone', 'Model server'],
                index: onDevice ? 0 : 1,
                onChanged: (i) => setLocal(() => onDevice = i == 0),
              ),
              const SizedBox(height: 14),
            ],
            if (onDevice)
              const Text('The v1 model runs inside this app. No Wi-Fi or computer is needed.')
            else ...[
              const Text('Type the address shown in the server window on the computer. '
                  'The phone and the computer must be on the same Wi-Fi.'),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Address'),
              ),
            ],
            const SizedBox(height: 18),
            PillButton(label: 'Save', primary: true, onPressed: () => Navigator.pop(ctx, true)),
          ]),
        ),
      ),
    );
    if (saved != true) return;
    final clean = controller.text.trim().replaceAll(RegExp(r'/+$'), '');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, onDevice ? 'device' : 'server');
    if (!onDevice && clean.isNotEmpty) await prefs.setString(_prefKey, clean);
    if (!mounted) return;
    setState(() {
      _onDevice = onDevice;
      if (!onDevice && clean.isNotEmpty) _server = clean;
      _error = null;
    });
    if (onDevice && _model != _ModelState.ready) _warmUp();
  }

  Future<void> _pick(ImageSource source) async {
    setState(() => _error = null);
    try {
      final file = await _picker.pickImage(source: source, preferredCameraDevice: CameraDevice.rear);
      if (file == null) return; // cancelled
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _image = bytes;
        _result = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = source == ImageSource.camera
          ? 'The camera could not be opened on this device. Use Upload image.'
          : 'The image could not be opened.');
    }
  }

  Future<void> _proceed() async {
    final image = _image;
    if (image == null || _busy) return;
    if (!_onDevice && _server.isEmpty) {
      await _editSettings();
      if (!_onDevice && _server.isEmpty) return;
    }
    setState(() {
      _busy = true;
      _busyText = 'Checking the photo';
      _error = null;
    });
    try {
      final CheckResult result;
      if (_onDevice) {
        result = await _engine.analyse(image, (text) {
          if (mounted) setState(() => _busyText = text);
        });
        if (mounted) _model = _ModelState.ready;
      } else {
        final watch = Stopwatch()..start();
        final response = await http
            .post(Uri.parse('$_server/api/predict'), headers: {'Content-Type': 'application/octet-stream'}, body: image)
            .timeout(const Duration(seconds: 90));
        final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        if (response.statusCode != 200) throw _ServerMessage(body['error'] as String? ?? 'The check failed.');
        result = CheckResult.fromJson(body, seconds: watch.elapsedMilliseconds / 1000);
      }
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _result = result;
        _view = 0;
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
    } on _ServerMessage catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on TimeoutException {
      if (mounted) setState(() => _error = 'The model server did not answer in time. Try again.');
    } catch (e) {
      // ignore: avoid_print
      print('CWSB_ERROR $e');
      if (mounted) {
        setState(() => _error = _onDevice
            ? 'The model could not check this photo on the phone. Try another photo. (${e.runtimeType})'
            : 'Cannot reach the model server at $_server. Check that it is running and that the address is right.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reset() {
    HapticFeedback.selectionClick();
    setState(() {
      _image = null;
      _result = null;
      _error = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  (String, Color) get _status {
    if (!_onDevice) return ('Using the model server', const Color(0xFF8FD3FF));
    return switch (_model) {
      _ModelState.ready => ('Model ready · works offline', const Color(0xFF7CF29A)),
      _ModelState.loading => ('Preparing the model', const Color(0xFFFFD166)),
      _ModelState.failed => ('The model could not be loaded', const Color(0xFFFF8A80)),
    };
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final (status, statusColor) = _status;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
      child: Scaffold(
        body: Column(children: [
          AppHeader(onSettings: _editSettings, status: status, statusColor: statusColor),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(
                  controller: _scroll,
                  // The page stops at its top and bottom edges; it cannot be dragged away from them.
                  physics: const ClampingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + MediaQuery.paddingOf(context).bottom),
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeIn,
                      layoutBuilder: (current, previous) => current ?? const SizedBox.shrink(),
                      child: result == null
                          ? Column(key: const ValueKey('input'), children: _inputSection())
                          : Column(key: ObjectKey(result), children: _resultSection(result)),
                    ),
                    const SizedBox(height: 18),
                    const _Footnote(),
                  ],
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------- input view

  List<Widget> _inputSection() {
    final p = Palette.of(context);
    final image = _image;
    return [
      AppCard(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                child: image == null
                    ? const EmptyStage(key: ValueKey('empty'))
                    : Stack(key: ObjectKey(image), fit: StackFit.expand, children: [
                        const ColoredBox(color: Color(0xFF0B0F0C)),
                        // Decoded at screen size, not at the camera's full size.
                        Image.memory(image, fit: BoxFit.contain, gaplessPlayback: true, cacheWidth: 1080),
                        if (_busy) ScanOverlay(text: _busyText),
                      ]),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (image == null)
            Row(children: [
              Expanded(
                child: ActionTile(
                  icon: Icons.photo_library_rounded,
                  title: 'Upload image',
                  caption: 'From the gallery',
                  onTap: () => _pick(ImageSource.gallery),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ActionTile(
                  icon: Icons.photo_camera_rounded,
                  title: 'Capture',
                  caption: 'Use the camera',
                  filled: true,
                  onTap: () => _pick(ImageSource.camera),
                ),
              ),
            ])
          else
            Row(children: [
              Expanded(child: PillButton(label: 'Change', icon: Icons.refresh_rounded, onPressed: _busy ? null : _reset)),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: PillButton(
                  label: _busy ? 'Checking' : 'Proceed',
                  icon: Icons.arrow_forward_rounded,
                  primary: true,
                  onPressed: _busy ? null : _proceed,
                ),
              ),
            ]),
        ]),
      ),
      if (_error != null) ...[const SizedBox(height: 12), NoteBox(text: _error!, error: true)],
      if (image == null) ...[
        const SizedBox(height: 16),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('For a reliable result', style: TextStyle(color: p.ink, fontSize: 16.5, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            const TipRow(
                icon: Icons.social_distance_rounded,
                title: 'Stand 2 to 3 m away',
                text: 'Show the whole plant. The model was trained on photos like this.'),
            const TipRow(
                icon: Icons.center_focus_strong_rounded,
                title: 'Keep the plant in the centre',
                text: 'The model looks at the centre square of the photo.'),
            const TipRow(
                icon: Icons.wb_sunny_rounded,
                title: 'Avoid glare and blur',
                text: 'Hold steady, and shade the plant if the sun is strong.',
                last: true),
          ]),
        ),
      ],
    ];
  }

  // --------------------------------------------------------- result view

  List<Widget> _resultSection(CheckResult r) {
    final p = Palette.of(context);
    return [
      Reveal(
        child: AppCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(23)),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [r.color, Color.lerp(r.color, Colors.black, 0.32)!],
                ),
              ),
              child: Row(children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                  ),
                  child: Icon(r.icon, color: Colors.white, size: 32),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r.label,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 31, fontWeight: FontWeight.w800, height: 1.05, letterSpacing: -0.5)),
                    const SizedBox(height: 4),
                    Text(r.detail, style: TextStyle(color: Colors.white.withValues(alpha: 0.93), fontSize: 14, height: 1.3)),
                  ]),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
              child: Row(children: [
                ScoreGauge(score: r.score, color: r.color),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Unhealthy score', style: TextStyle(color: p.muted, fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    BandBar(score: r.score, low: r.tLow, high: r.tHigh),
                    const SizedBox(height: 8),
                    Text(
                      'Below ${r.tLow.toStringAsFixed(2)} is healthy. ${r.tHigh.toStringAsFixed(2)} or above is unhealthy.',
                      style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.35),
                    ),
                  ]),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Row(children: [
                Expanded(child: StatChip(icon: Icons.analytics_rounded, label: 'Exact score', value: r.score.toStringAsFixed(4))),
                const SizedBox(width: 8),
                Expanded(child: StatChip(icon: Icons.timer_rounded, label: 'Time', value: '${r.seconds.toStringAsFixed(1)} s')),
                const SizedBox(width: 8),
                Expanded(
                  child: StatChip(
                      icon: r.source == 'on this phone' ? Icons.smartphone_rounded : Icons.dns_rounded,
                      label: 'Model ran',
                      value: r.source == 'on this phone' ? 'On phone' : 'Server'),
                ),
              ]),
            ),
          ]),
        ),
      ),
      if (r.qualityNote != null) ...[
        const SizedBox(height: 12),
        Reveal(delay: const Duration(milliseconds: 90), child: NoteBox(text: r.qualityNote!)),
      ],
      const SizedBox(height: 16),
      Reveal(
        delay: const Duration(milliseconds: 140),
        child: AppCard(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 12),
              child: Text('Where the model looked', style: TextStyle(color: p.ink, fontSize: 16.5, fontWeight: FontWeight.w800)),
            ),
            SegmentSwitch(
              labels: const ['Heatmap', 'Photo', 'Compare'],
              index: _view,
              onChanged: (i) {
                HapticFeedback.selectionClick();
                setState(() => _view = i);
              },
            ),
            const SizedBox(height: 12),
            HeatView(photo: r.photo, heatmap: r.heatmap, mode: _view),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 12, 6, 0),
              child: Row(children: [
                Text('less', style: TextStyle(color: p.muted, fontSize: 12)),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      gradient: const LinearGradient(colors: [
                        Color(0xFF00007F),
                        Color(0xFF0000FF),
                        Color(0xFF00FFFF),
                        Color(0xFFFFFF00),
                        Color(0xFFFF0000),
                        Color(0xFF7F0000),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('more influence', style: TextStyle(color: p.muted, fontSize: 12)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 10, 6, 4),
              child: Text(
                _view == 2
                    ? 'Drag the handle to compare the photo with the heatmap.'
                    : 'Red areas pushed the model most towards its answer. The model sees the centre square of the photo.',
                style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.35),
              ),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      Reveal(
        delay: const Duration(milliseconds: 200),
        child: PillButton(label: 'Check another photo', icon: Icons.add_a_photo_rounded, primary: true, onPressed: _reset),
      ),
    ];
  }
}

class _Footnote extends StatelessWidget {
  const _Footnote();

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.shield_outlined, size: 16, color: p.muted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'A screening aid, model v1. Trained on whole-plant photos, so it is less reliable on close-ups.',
            style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.35),
          ),
        ),
      ]),
    );
  }
}
