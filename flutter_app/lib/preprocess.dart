import 'dart:math' as math;
import 'dart:typed_data';

/// Photo preparation that reproduces the training pipeline pixel for pixel.
///
/// The training code resizes with Pillow (short side to 416, antialiased
/// bilinear) and cuts the centre 384x384 square. A phone's built-in image
/// scaling gives slightly different pixels and so slightly different scores,
/// so the same arithmetic as Pillow is done here instead.
class Prepared {
  Prepared(this.rgb, this.qualityNote);

  /// 384 x 384 x 3 bytes, the model input.
  final Uint8List rgb;
  final String? qualityNote;
}

const _img = 384, _resize = 416;
const _blurMin = 60.0, _clippedMax = 0.20, _darkMax = 0.40;

/// [rgba] is the fully decoded photo (upright), 4 bytes per pixel.
Prepared prepare(Uint8List rgba, int width, int height) {
  final note = _qualityNote(rgba, width, height);
  final ow = width <= height ? _resize : (_resize * width / height).floor();
  final oh = width <= height ? (_resize * height / width).floor() : _resize;
  // Pillow resizes in two passes: across, then down, rounding to bytes in between.
  final across = _resamplePass(rgba, width, height, 4, ow, horizontal: true);
  final small = _resamplePass(across, ow, height, 3, oh, horizontal: false);
  final left = _pyRound(ow - _img), top = _pyRound(oh - _img);
  final rgb = Uint8List(_img * _img * 3);
  for (var y = 0; y < _img; y++) {
    final from = ((y + top) * ow + left) * 3;
    rgb.setRange(y * _img * 3, (y + 1) * _img * 3, small, from);
  }
  return Prepared(rgb, note);
}

/// Python's round((size - 384) / 2): halves round to the even number.
int _pyRound(int diff) {
  final half = diff ~/ 2;
  return diff.isEven || half.isEven ? half : half + 1;
}

/// One pass of Pillow's ImagingResample with the bilinear (triangle) filter.
/// Input has [inChannels] bytes per pixel (alpha ignored); output is RGB.
Uint8List _resamplePass(Uint8List src, int w, int h, int inChannels, int outSize, {required bool horizontal}) {
  const precision = 22; // Pillow: 32 - 8 - 2
  final inSize = horizontal ? w : h;
  final scale = inSize / outSize;
  final filterScale = math.max(scale, 1.0);
  final support = filterScale; // bilinear support is 1.0
  final kSize = support.ceil() * 2 + 1;
  final bounds = Int32List(outSize * 2);
  final coeffs = Int32List(outSize * kSize);
  final tmp = Float64List(kSize);
  for (var o = 0; o < outSize; o++) {
    final center = (o + 0.5) * scale;
    var lo = (center - support + 0.5).toInt();
    if (lo < 0) lo = 0;
    var hi = (center + support + 0.5).toInt();
    if (hi > inSize) hi = inSize;
    final n = hi - lo;
    var total = 0.0;
    for (var x = 0; x < n; x++) {
      var v = (x + lo - center + 0.5) / filterScale;
      if (v < 0) v = -v;
      final k = v < 1.0 ? 1.0 - v : 0.0;
      tmp[x] = k;
      total += k;
    }
    for (var x = 0; x < n; x++) {
      final k = total != 0 ? tmp[x] / total : tmp[x];
      coeffs[o * kSize + x] = (k < 0 ? -0.5 + k * (1 << precision) : 0.5 + k * (1 << precision)).toInt();
    }
    bounds[o * 2] = lo;
    bounds[o * 2 + 1] = n;
  }
  const half = 1 << (precision - 1);
  final ow = horizontal ? outSize : w, oh = horizontal ? h : outSize;
  final out = Uint8List(ow * oh * 3);
  if (horizontal) {
    for (var y = 0; y < h; y++) {
      final row = y * w * inChannels;
      for (var o = 0; o < outSize; o++) {
        final lo = bounds[o * 2], n = bounds[o * 2 + 1], kb = o * kSize;
        var r = half, g = half, b = half;
        for (var x = 0; x < n; x++) {
          final k = coeffs[kb + x], i = row + (lo + x) * inChannels;
          r += src[i] * k;
          g += src[i + 1] * k;
          b += src[i + 2] * k;
        }
        final d = (y * ow + o) * 3;
        out[d] = _clip(r >> precision);
        out[d + 1] = _clip(g >> precision);
        out[d + 2] = _clip(b >> precision);
      }
    }
  } else {
    for (var o = 0; o < outSize; o++) {
      final lo = bounds[o * 2], n = bounds[o * 2 + 1], kb = o * kSize;
      for (var x = 0; x < w; x++) {
        var r = half, g = half, b = half;
        for (var y = 0; y < n; y++) {
          final k = coeffs[kb + y], i = ((lo + y) * w + x) * inChannels;
          r += src[i] * k;
          g += src[i + 1] * k;
          b += src[i + 2] * k;
        }
        final d = (o * ow + x) * 3;
        out[d] = _clip(r >> precision);
        out[d + 1] = _clip(g >> precision);
        out[d + 2] = _clip(b >> precision);
      }
    }
  }
  return out;
}

int _clip(int v) => v < 0 ? 0 : (v > 255 ? 255 : v);

/// Blur, glare and darkness check with the limits of the training pipeline:
/// grey image, shrunk to 1024 wide if larger, variance of the Laplacian.
String? _qualityNote(Uint8List rgba, int w, int h) {
  final grey = Uint8List(w * h);
  for (var i = 0, p = 0; i < w * h; i++, p += 4) {
    grey[i] = (rgba[p] * 4899 + rgba[p + 1] * 9617 + rgba[p + 2] * 1868 + 8192) >> 14; // OpenCV's weights
  }
  var g = grey, gw = w, gh = h;
  if (w > 1024) {
    gw = 1024;
    gh = math.max((h * (1024 / w)).toInt(), 1);
    g = Uint8List(gw * gh);
    final sx = w / gw, sy = h / gh;
    for (var y = 0; y < gh; y++) {
      final fy = math.max((y + 0.5) * sy - 0.5, 0.0);
      final y0 = math.min(fy.floor(), h - 1), y1 = math.min(y0 + 1, h - 1);
      final ty = fy - y0;
      for (var x = 0; x < gw; x++) {
        final fx = math.max((x + 0.5) * sx - 0.5, 0.0);
        final x0 = math.min(fx.floor(), w - 1), x1 = math.min(x0 + 1, w - 1);
        final tx = fx - x0;
        final top = grey[y0 * w + x0] * (1 - tx) + grey[y0 * w + x1] * tx;
        final bottom = grey[y1 * w + x0] * (1 - tx) + grey[y1 * w + x1] * tx;
        g[y * gw + x] = (top * (1 - ty) + bottom * ty).round();
      }
    }
  }
  final n = gw * gh;
  var clipped = 0, dark = 0;
  var sum = 0.0, sumSq = 0.0;
  for (var y = 0; y < gh; y++) {
    final up = (y == 0 ? math.min(1, gh - 1) : y - 1) * gw, down = (y == gh - 1 ? math.max(gh - 2, 0) : y + 1) * gw;
    for (var x = 0; x < gw; x++) {
      final v = g[y * gw + x];
      if (v > 250) clipped++;
      if (v < 15) dark++;
      final l = x == 0 ? math.min(1, gw - 1) : x - 1, r = x == gw - 1 ? math.max(gw - 2, 0) : x + 1;
      final lap = (g[up + x] + g[down + x] + g[y * gw + l] + g[y * gw + r] - 4 * v).toDouble();
      sum += lap;
      sumSq += lap * lap;
    }
  }
  final mean = sum / n, blur = sumSq / n - mean * mean;
  if (blur < _blurMin) return 'The photo looks blurry. Hold steady and retake for a more reliable result.';
  if (clipped / n > _clippedMax) return 'Too much glare. Shade the plant and retake for a more reliable result.';
  if (dark / n > _darkMax) return 'The photo is too dark. Retake in better light for a more reliable result.';
  return null;
}
