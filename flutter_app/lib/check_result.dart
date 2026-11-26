import 'dart:convert';
import 'dart:typed_data';

/// The answer for one photo, from the model on the phone or from the model server.
class CheckResult {
  CheckResult({
    required this.label,
    required this.detail,
    required this.score,
    required this.tLow,
    required this.tHigh,
    required this.qualityNote,
    required this.photo,
    required this.heatmap,
    required this.source,
    required this.seconds,
  });

  factory CheckResult.fromJson(Map<String, dynamic> j, {required double seconds}) => CheckResult(
        label: j['label'] as String,
        detail: j['detail'] as String,
        score: (j['score'] as num).toDouble(),
        tLow: (j['t_low'] as num).toDouble(),
        tHigh: (j['t_high'] as num).toDouble(),
        qualityNote: j['quality_note'] as String?,
        photo: _decode(j['photo'] as String),
        heatmap: _decode(j['heatmap'] as String),
        source: 'model server',
        seconds: seconds,
      );

  final String label, detail;
  final double score, tLow, tHigh;
  final String? qualityNote;

  /// Encoded images (PNG or JPEG) of the 384x384 square the model saw.
  final Uint8List photo, heatmap;

  /// Where the model ran: 'on this phone' or 'model server'.
  final String source;
  final double seconds;

  static Uint8List _decode(String dataUrl) => base64Decode(dataUrl.substring(dataUrl.indexOf(',') + 1));

  /// Same wording and thresholds as the model server.
  static (String, String) labelFor(double score, double tLow, double tHigh) {
    if (score >= tHigh) return ('Unhealthy', 'Signs of white stem borer are likely.');
    if (score < tLow) return ('Healthy', 'No visible signs of white stem borer.');
    return ('Unsure', 'The model cannot decide from this photo. Retake it, or check the plant by hand.');
  }
}
