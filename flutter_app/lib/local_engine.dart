import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path_provider/path_provider.dart';

import 'cam.dart';
import 'check_result.dart';
import 'preprocess.dart';

/// The model can run inside the app on phones.
bool get localSupported => Platform.isAndroid || Platform.isIOS;

/// Runs the v1 model inside the app: no server and no network.
///
/// The score comes from `cwsb_v1.onnx`; the heatmap is Grad-CAM computed from
/// the model's own 12x12 feature grid (see cam.dart). Photo preparation and
/// heatmap arithmetic run on worker threads so the screen stays smooth.
class LocalEngine {
  static const _img = 384;

  OrtSession? _session;
  Future<void>? _loading;
  late Float64List _gamma;
  late List<Float64List> _fc;
  late Uint8List _jet;
  late double _eps, _tLow, _tHigh;

  /// Loads the model ahead of the first photo. Safe to call more than once.
  Future<void> warmUp() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final head = jsonDecode(await rootBundle.loadString('assets/cwsb_v1_head.json')) as Map<String, dynamic>;
      _gamma = Float64List.fromList([for (final v in head['gamma'] as List) (v as num).toDouble()]);
      _fc = [
        for (final row in head['fc'] as List) Float64List.fromList([for (final v in row as List) (v as num).toDouble()])
      ];
      _jet = Uint8List.fromList([for (final v in head['jet'] as List) v as int]);
      _eps = (head['eps'] as num).toDouble();
      _tLow = (head['t_low'] as num).toDouble();
      _tHigh = (head['t_high'] as num).toDouble();

      // ONNX Runtime opens the model from a file, so copy it out of the app once.
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/cwsb_v1.onnx');
      if (!await file.exists() || await file.length() != head['onnx_bytes'] as int) {
        final data = await rootBundle.load('assets/cwsb_v1.onnx');
        await file.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
      }
      OrtEnv.instance.init();
      final options = OrtSessionOptions()..setIntraOpNumThreads(Platform.numberOfProcessors.clamp(1, 4));
      _session = OrtSession.fromFile(file, options);
    } catch (_) {
      _loading = null; // allow another try
      rethrow;
    }
  }

  Future<CheckResult> analyse(Uint8List bytes, void Function(String) onStatus) async {
    final watch = Stopwatch()..start();
    if (_session == null) onStatus('Preparing the model');
    await warmUp();
    onStatus('Checking the photo');

    // Decode the photo upright at full size, then prepare it exactly as the
    // training pipeline does (see preprocess.dart).
    final full = await _decode(bytes);
    final prepared = await _prepare(full.rgba, full.width, full.height);

    // One forward pass of the model, on its own thread.
    final input = OrtValueTensor.createTensorWithDataList(prepared.rgb, [_img, _img, 3]);
    final runOptions = OrtRunOptions();
    final outputs = await _session!.runAsync(runOptions, {'rgb_384': input}, ['probabilities', 'feature_map']);
    final score = ((((outputs![0]!.value as List)[0]) as List)[1] as num).toDouble();
    final feature = (outputs[1]!.value as List)[0] as List; // [768][12][12]
    final channels = feature.length, grid = (feature[0] as List).length, cells = grid * grid;
    final flat = Float64List(channels * cells);
    for (var c = 0; c < channels; c++) {
      final plane = feature[c] as List;
      for (var y = 0; y < grid; y++) {
        final row = plane[y] as List;
        for (var x = 0; x < grid; x++) {
          flat[c * cells + y * grid + x] = (row[x] as num).toDouble();
        }
      }
    }
    input.release();
    runOptions.release();
    for (final o in outputs) {
      o?.release();
    }

    // Heatmap for the class shown (Unhealthy unless the result is Healthy).
    final images = await _heatmap(CamInput(
      features: flat,
      channels: channels,
      grid: grid,
      rgb: prepared.rgb,
      gamma: _gamma,
      classWeights: _fc[score >= _tLow ? 1 : 0],
      eps: _eps,
      jet: _jet,
    ));
    final (label, detail) = CheckResult.labelFor(score, _tLow, _tHigh);
    final result = CheckResult(
      label: label,
      detail: detail,
      score: score,
      tLow: _tLow,
      tHigh: _tHigh,
      qualityNote: prepared.qualityNote,
      photo: await _png(images.photo, _img, _img),
      heatmap: await _png(images.heatmap, _img, _img),
      source: 'on this phone',
      seconds: watch.elapsedMilliseconds / 1000,
    );
    // One line in the device log, so a test can read the exact score.
    // ignore: avoid_print
    print('CWSB_RESULT ${jsonEncode({'score': score, 'label': label, 'seconds': result.seconds, 'source': 'device'})}');
    return result;
  }

  // ------------------------------------------------------------- helpers
  // Each worker call sits in its own function so that only its arguments are
  // sent to the worker thread.

  static Future<Prepared> _prepare(Uint8List rgba, int width, int height) =>
      Isolate.run(() => prepare(rgba, width, height));

  static Future<CamOutput> _heatmap(CamInput input) => Isolate.run(() => buildHeatmap(input));

  static Future<({Uint8List rgba, int width, int height})> _decode(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final codec = await ui.instantiateImageCodecFromBuffer(buffer);
    final image = (await codec.getNextFrame()).image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    final out = (rgba: data!.buffer.asUint8List(), width: image.width, height: image.height);
    image.dispose();
    codec.dispose();
    return out;
  }

  static Future<Uint8List> _png(Uint8List rgba, int w, int h) async {
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(rgba, w, h, ui.PixelFormat.rgba8888, done.complete);
    final image = await done.future;
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }
}
