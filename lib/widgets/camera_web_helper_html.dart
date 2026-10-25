import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

class _WebCamRegistry {
  static final Map<String, html.VideoElement> videoElements = {};
  static StreamSubscription<html.Geoposition>? locationSubscription;
}

abstract class CameraWebHelper {
  static Widget buildWebCameraView(String viewId) {
    return HtmlElementView(viewType: viewId);
  }

  static void startWebCamera(String viewId, Function(dynamic stream) onStreamStarted, {bool isFrontCamera = false}) {
    final videoElement = html.VideoElement()
      ..autoplay = true
      ..muted = true
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'cover'
      ..style.transform = isFrontCamera ? 'scaleX(-1)' : 'none';

    _WebCamRegistry.videoElements[viewId] = videoElement;
    ui_web.platformViewRegistry.registerViewFactory(viewId, (int id) => videoElement);

    final String facing = isFrontCamera ? 'user' : 'environment';

    html.window.navigator.mediaDevices?.getUserMedia({
      'video': {
        'facingMode': {'ideal': facing},
        'width': {'ideal': 1280},
        'height': {'ideal': 720},
      }
    }).then((stream) {
      videoElement.srcObject = stream;
      videoElement.play();
      onStreamStarted(stream);
    }).catchError((err) {
      html.window.navigator.mediaDevices?.getUserMedia({'video': true}).then((stream) {
        videoElement.srcObject = stream;
        videoElement.play();
        onStreamStarted(stream);
      });
    });
  }

  /// Start HTML5 continuous browser location tracking with accuracy reporting
  static void watchBrowserLocation(
    Function(double lat, double lng, double accuracy, DateTime timestamp, String? address) onLocationUpdate,
    Function(String errorMessage) onError,
  ) {
    try {
      _WebCamRegistry.locationSubscription?.cancel();

      _WebCamRegistry.locationSubscription = html.window.navigator.geolocation.watchPosition(
        enableHighAccuracy: true,
        timeout: const Duration(seconds: 10),
        maximumAge: const Duration(seconds: 0),
      ).listen(
        (html.Geoposition pos) {
          final coords = pos.coords;
          if (coords != null) {
            final rawLat = coords.latitude;
            final rawLng = coords.longitude;
            final rawAcc = coords.accuracy;
            if (rawLat != null && rawLng != null) {
              final double lat = rawLat.toDouble();
              final double lng = rawLng.toDouble();
              final double accuracy = (rawAcc != null) ? rawAcc.toDouble() : 999.0;

              onLocationUpdate(lat, lng, accuracy, DateTime.now(), null);
            }
          }
        },
        onError: (err) {
          String msg = 'Unable to get current location. Please enable GPS and try again.';
          onError(msg);
        },
      );
    } catch (e) {
      onError('Unable to get current location. Please enable GPS and try again.');
    }
  }

  static void stopBrowserLocation() {
    _WebCamRegistry.locationSubscription?.cancel();
    _WebCamRegistry.locationSubscription = null;
  }

  static String? captureWebCameraFrame(
    String viewId, {
    bool isFrontCamera = false,
    String? locationAddress,
    String? latLngText,
    String? timestampText,
    String? accuracyText,
  }) {
    final video = _WebCamRegistry.videoElements[viewId];
    if (video != null && video.videoWidth > 0 && video.videoHeight > 0) {
      final width = video.videoWidth;
      final height = video.videoHeight;
      final canvas = html.CanvasElement(
        width: width,
        height: height,
      );
      final ctx = canvas.context2D;
      if (isFrontCamera) {
        ctx.translate(width, 0);
        ctx.scale(-1, 1);
      }
      ctx.drawImage(video, 0, 0);

      if (isFrontCamera) {
        ctx.setTransform(1, 0, 0, 1, 0, 0);
      }

      String line1 = 'GPS Location Captured';
      String line2 = '';

      if (locationAddress != null && locationAddress.trim().isNotEmpty) {
        final fullLoc = locationAddress.trim();
        if (fullLoc.contains('\n')) {
          final parts = fullLoc.split('\n');
          line1 = parts.first;
          line2 = parts.sublist(1).join(', ');
        } else {
          final parts = fullLoc.split(', ');
          if (parts.length > 3) {
            final mid = (parts.length / 2).ceil();
            line1 = parts.take(mid).join(', ');
            line2 = parts.skip(mid).join(', ');
          } else {
            line1 = fullLoc;
            line2 = '';
          }
        }
      }

      final gps = (latLngText != null && latLngText.trim().isNotEmpty)
          ? latLngText.trim()
          : '';
      final timeStr = timestampText ?? DateTime.now().toString().split('.').first;

      final barHeight = (height * 0.26).clamp(100.0, 170.0);
      final barTop = height - barHeight;

      ctx.fillStyle = 'rgba(15, 23, 42, 0.92)';
      ctx.fillRect(0, barTop, width.toDouble(), barHeight);

      // Bright cyan accent top border
      ctx.fillStyle = '#00E676';
      ctx.fillRect(0, barTop, width.toDouble(), 4);

      final fontSize = (height * 0.028).clamp(12.0, 18.0);

      // Line 1: Header Title (Bold White)
      ctx.font = 'bold ${fontSize + 1}px sans-serif';
      ctx.fillStyle = '#FFFFFF';
      ctx.fillText(line1, 16, barTop + fontSize + 8);

      // Line 2: Sub-Address (Light White)
      if (line2.isNotEmpty) {
        ctx.font = '${fontSize * 0.88}px sans-serif';
        ctx.fillStyle = '#E2E8F0';
        ctx.fillText(line2, 16, barTop + (fontSize * 2) + 12);
      }

      // Line 3: Coordinates (Light Cyan)
      ctx.font = '${fontSize * 0.85}px sans-serif';
      ctx.fillStyle = '#38BDF8';
      ctx.fillText(gps, 16, barTop + (fontSize * 3) + 16);

      // Line 4: Timestamp (Light Green)
      ctx.font = '${fontSize * 0.85}px sans-serif';
      ctx.fillStyle = '#A7F3D0';
      ctx.fillText(timeStr, 16, barTop + (fontSize * 4) + 20);

      return canvas.toDataUrl('image/jpeg', 0.92);
    }
    return null;
  }

  static void fetchBrowserLocation(Function(double lat, double lng, String? resolvedAddress) onLocationFound) async {
    try {
      html.window.navigator.geolocation.getCurrentPosition(
        enableHighAccuracy: true,
        timeout: const Duration(seconds: 15),
        maximumAge: const Duration(seconds: 0),
      ).then((pos) async {
        final coords = pos.coords;
        if (coords != null) {
          final rawLat = coords.latitude;
          final rawLng = coords.longitude;
          if (rawLat != null && rawLng != null) {
            final lat = rawLat.toDouble();
            final lng = rawLng.toDouble();
            onLocationFound(lat, lng, null);
          }
        }
      });
    } catch (_) {}
  }

  static void stopWebCameraStream(dynamic stream) {
    if (stream is html.MediaStream) {
      for (var track in stream.getTracks()) {
        track.stop();
      }
    }
  }

  static void pickGalleryImage(Function(String base64Url) onImagePicked) {
    final uploadInput = html.FileUploadInputElement()..accept = 'image/*';
    uploadInput.click();

    uploadInput.onChange.listen((e) {
      final files = uploadInput.files;
      if (files != null && files.isNotEmpty) {
        final file = files[0];
        final reader = html.FileReader();
        reader.readAsDataUrl(file);
        reader.onLoadEnd.listen((e) {
          if (reader.result != null) {
            onImagePicked(reader.result.toString());
          }
        });
      }
    });
  }
}
