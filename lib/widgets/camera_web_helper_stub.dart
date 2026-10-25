import 'package:flutter/material.dart';

abstract class CameraWebHelper {
  static Widget buildWebCameraView(String viewId) {
    return const SizedBox();
  }

  static void startWebCamera(String viewId, Function(dynamic stream) onStreamStarted, {bool isFrontCamera = false}) {}

  static void watchBrowserLocation(
    Function(double lat, double lng, double accuracy, DateTime timestamp, String? address) onLocationUpdate,
    Function(String errorMessage) onError,
  ) {}

  static void stopBrowserLocation() {}

  static String? captureWebCameraFrame(
    String viewId, {
    bool isFrontCamera = false,
    String? locationAddress,
    String? latLngText,
    String? timestampText,
    String? accuracyText,
  }) {
    return null;
  }

  static void stopWebCameraStream(dynamic stream) {}

  static void fetchBrowserLocation(Function(double lat, double lng, String? resolvedAddress) onLocationFound) {}

  static void pickGalleryImage(Function(String base64Url) onImagePicked) {}
}
