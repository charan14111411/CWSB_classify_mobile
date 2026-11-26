import 'dart:math' as math;
import 'dart:typed_data';

/// Heatmap arithmetic, kept free of Flutter so it can run on a worker thread.
///
/// Grad-CAM for the v1 model. The head is average-pool -> LayerNorm -> one
/// linear layer, so the gradient Grad-CAM needs has a closed form and no
/// backward pass is required. Checked against PyTorch: identical to 6 decimals.
class CamInput {
  CamInput({
    required this.features,
    required this.channels,
    required this.grid,
    required this.rgb,
    required this.gamma,
    required this.classWeights,
    required this.eps,
    required this.jet,
  });

  /// Model output `feature_map`, flattened as [channels][grid][grid].
  final Float64List features;
  final int channels, grid;

  /// The 384x384x3 photo the model saw.
  final Uint8List rgb;

  /// LayerNorm weights and the linear-layer row of the class being explained.
  final Float64List gamma, classWeights;
  final double eps;

  /// OpenCV's JET colour table, 256 x RGB.
  final Uint8List jet;
}

class CamOutput {
  CamOutput(this.photo, this.heatmap);

  /// 384x384 RGBA images: the photo, and the photo with the heat colours on it.
  final Uint8List photo, heatmap;
}

const _img = 384;

CamOutput buildHeatmap(CamInput d) {
  final channels = d.channels, cells = d.grid * d.grid, a = d.features;
  final pooled = Float64List(channels);
  var mu = 0.0;
  for (var c = 0; c < channels; c++) {
    var s = 0.0;
    for (var i = 0; i < cells; i++) {
      s += a[c * cells + i];
    }
    pooled[c] = s / cells;
    mu += pooled[c];
  }
  mu /= channels;
  var variance = 0.0;
  for (var c = 0; c < channels; c++) {
    variance += (pooled[c] - mu) * (pooled[c] - mu);
  }
  final sigma = math.sqrt(variance / channels + d.eps);
  var meanV = 0.0, meanVz = 0.0;
  for (var c = 0; c < channels; c++) {
    final v = d.gamma[c] * d.classWeights[c];
    meanV += v;
    meanVz += v * (pooled[c] - mu) / sigma;
  }
  meanV /= channels;
  meanVz /= channels;
  final cam = Float64List(cells);
  for (var c = 0; c < channels; c++) {
    final z = (pooled[c] - mu) / sigma;
    final weight = (d.gamma[c] * d.classWeights[c] - meanV - z * meanVz) / sigma; // d(logit) / d(pooled feature)
    for (var i = 0; i < cells; i++) {
      cam[i] += weight * a[c * cells + i];
    }
  }
  for (var i = 0; i < cells; i++) {
    if (cam[i] < 0) cam[i] = 0;
  }
  final big = _bicubic(cam, d.grid, _img);
  var lo = double.infinity, hi = -double.infinity;
  for (var i = 0; i < big.length; i++) {
    if (big[i] < 0) big[i] = 0;
    lo = math.min(lo, big[i]);
    hi = math.max(hi, big[i]);
  }
  final range = hi - lo;

  final photo = Uint8List(_img * _img * 4), heat = Uint8List(_img * _img * 4);
  for (var p = 0; p < _img * _img; p++) {
    final v = range > 1e-9 ? (big[p] - lo) / range : 0.0;
    final j = (v * 255).toInt() * 3;
    final alpha = 0.15 + 0.5 * v; // stronger colour where the model looked
    for (var ch = 0; ch < 3; ch++) {
      final px = d.rgb[p * 3 + ch];
      photo[p * 4 + ch] = px;
      heat[p * 4 + ch] = (px * (1 - alpha) + d.jet[j + ch] * alpha).toInt();
    }
    photo[p * 4 + 3] = 255;
    heat[p * 4 + 3] = 255;
  }
  return CamOutput(photo, heat);
}

/// Bicubic upsampling as PyTorch does it (a = -0.75, align_corners = False).
Float64List _bicubic(Float64List src, int n, int out) {
  const a = -0.75;
  final index = Int32List(out * 4);
  final weight = Float64List(out * 4);
  for (var d = 0; d < out; d++) {
    final s = (d + 0.5) * n / out - 0.5;
    final f = s.floor();
    final t = s - f;
    weight[d * 4] = ((a * (t + 1) - 5 * a) * (t + 1) + 8 * a) * (t + 1) - 4 * a;
    weight[d * 4 + 1] = ((a + 2) * t - (a + 3)) * t * t + 1;
    weight[d * 4 + 2] = ((a + 2) * (1 - t) - (a + 3)) * (1 - t) * (1 - t) + 1;
    weight[d * 4 + 3] = ((a * (2 - t) - 5 * a) * (2 - t) + 8 * a) * (2 - t) - 4 * a;
    for (var k = 0; k < 4; k++) {
      index[d * 4 + k] = (f - 1 + k).clamp(0, n - 1);
    }
  }
  final rows = Float64List(n * out); // widen each source row
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < out; x++) {
      var v = 0.0;
      for (var k = 0; k < 4; k++) {
        v += weight[x * 4 + k] * src[y * n + index[x * 4 + k]];
      }
      rows[y * out + x] = v;
    }
  }
  final result = Float64List(out * out);
  for (var y = 0; y < out; y++) {
    for (var x = 0; x < out; x++) {
      var v = 0.0;
      for (var k = 0; k < 4; k++) {
        v += weight[y * 4 + k] * rows[index[y * 4 + k] * out + x];
      }
      result[y * out + x] = v;
    }
  }
  return result;
}
