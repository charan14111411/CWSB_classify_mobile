import 'dart:typed_data';

import 'check_result.dart';

/// Used where the model cannot run inside the app (the browser build).
bool get localSupported => false;

class LocalEngine {
  Future<void> warmUp() async {}

  Future<CheckResult> analyse(Uint8List bytes, void Function(String) onStatus) =>
      throw UnsupportedError('The model cannot run inside this app here. Use the model server.');
}
