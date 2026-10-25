import 'package:flutter/foundation.dart';

class SpeechWebHelper {
  static bool get isSupported => false;

  static dynamic createRecognition({
    required Function(String transcript) onResult,
    required VoidCallback onError,
    required VoidCallback onEnd,
  }) {
    return null;
  }

  static void start(dynamic recognition) {}

  static void stop(dynamic recognition) {}
}
