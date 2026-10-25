import 'dart:html' as html;
import 'package:flutter/foundation.dart';

class SpeechWebHelper {
  static bool get isSupported {
    try {
      return html.SpeechRecognition.supported;
    } catch (_) {
      return false;
    }
  }

  static dynamic createRecognition({
    required Function(String transcript) onResult,
    required VoidCallback onError,
    required VoidCallback onEnd,
  }) {
    try {
      if (!isSupported) return null;
      final recognition = html.SpeechRecognition();
      recognition.continuous = true;
      recognition.interimResults = true;
      recognition.lang = 'en-US';

      recognition.onResult.listen((event) {
        final results = event.results;
        if (results != null && results.isNotEmpty) {
          String recognized = '';
          for (var i = 0; i < results.length; i++) {
            final transcript = results[i].item(0).transcript;
            if (transcript != null) {
              recognized += '$transcript ';
            }
          }
          if (recognized.trim().isNotEmpty) {
            onResult(recognized.trim());
          }
        }
      });

      recognition.onError.listen((err) {
        debugPrint('Speech recognition error: $err');
        onError();
      });

      recognition.onEnd.listen((_) {
        onEnd();
      });

      return recognition;
    } catch (e) {
      debugPrint('SpeechWebHelper createRecognition error: $e');
      return null;
    }
  }

  static void start(dynamic recognition) {
    if (recognition != null) {
      try {
        recognition.start();
      } catch (_) {}
    }
  }

  static void stop(dynamic recognition) {
    if (recognition != null) {
      try {
        recognition.stop();
      } catch (_) {}
    }
  }
}
