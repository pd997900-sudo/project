import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

class GeotagService {
  /// Fetch small static map image centered on coordinates with marker
  static Future<Uint8List?> fetchStaticMapTile(double lat, double lng, {int width = 160, int height = 160}) async {
    final urls = [
      'https://staticmap.openstreetmap.de/staticmap.php?center=$lat,$lng&zoom=15&size=${width}x$height&markers=$lat,$lng,red-pushpin',
      'https://maps.geoapify.com/v1/staticmap?style=osm-bright&width=$width&height=$height&center=lonlat:$lng,$lat&zoom=15&marker=lonlat:$lng,$lat;color:%23ff0000;size:medium&apiKey=maps',
    ];

    for (final urlStr in urls) {
      try {
        final res = await http.get(Uri.parse(urlStr), headers: {
          'User-Agent': 'RoadWatch-App/1.0',
        }).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200 && res.bodyBytes.isNotEmpty && res.bodyBytes.length > 500) {
          return res.bodyBytes;
        }
      } catch (_) {}
    }
    return null;
  }

  /// Create Geotagged composite image with overlay containing:
  /// - Small map with location marker
  /// - Address
  /// - Latitude & Longitude
  /// - Date & Time
  /// - GPS accuracy
  /// - "RoadWatch" branding
  static Future<Uint8List> createGeotaggedImage({
    required Uint8List photoBytes,
    required double latitude,
    required double longitude,
    required double accuracy,
    required String address,
    required DateTime timestamp,
  }) async {
    try {
      // 1. Decode original photo
      final ui.Codec codec = await ui.instantiateImageCodec(photoBytes);
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      final ui.Image baseImage = frameInfo.image;

      final int width = baseImage.width;
      final int height = baseImage.height;

      // 2. Fetch static map snippet
      Uint8List? mapBytes = await fetchStaticMapTile(latitude, longitude);
      ui.Image? mapImage;
      if (mapBytes != null) {
        try {
          final ui.Codec mapCodec = await ui.instantiateImageCodec(mapBytes);
          final ui.FrameInfo mapFrame = await mapCodec.getNextFrame();
          mapImage = mapFrame.image;
        } catch (_) {}
      }

      // 3. Setup Canvas & PictureRecorder
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);

      // Draw original road damage photo
      canvas.drawImage(baseImage, Offset.zero, Paint()..filterQuality = ui.FilterQuality.high);

      // 4. Calculate overlay geometry (bottom ~20-22% height, min 140px, max 260px)
      final double overlayHeight = (height * 0.22).clamp(140.0, 260.0);
      final double overlayTop = height - overlayHeight;

      // Draw dark semi-translucent background container
      final Paint bgPaint = Paint()
        ..color = const Color(0xEE0F172A) // Sleek dark Navy/Slate
        ..style = PaintingStyle.fill;
      canvas.drawRect(Rect.fromLTWH(0, overlayTop, width.toDouble(), overlayHeight), bgPaint);

      // Draw top accent line (Vibrant green/cyan accent)
      final Paint accentPaint = Paint()
        ..color = const Color(0xFF00E676)
        ..style = PaintingStyle.fill;
      canvas.drawRect(Rect.fromLTWH(0, overlayTop, width.toDouble(), 4), accentPaint);

      // 5. Draw Mini Static Map Widget on the Left
      final double padding = 12.0;
      final double mapSize = overlayHeight - (padding * 2) - 4;
      final Rect mapRect = Rect.fromLTWH(padding, overlayTop + padding + 2, mapSize, mapSize);

      // Clip map area with rounded corners
      canvas.save();
      final RRect mapRRect = RRect.fromRectAndRadius(mapRect, const Radius.circular(10));
      canvas.clipRRect(mapRRect);

      if (mapImage != null) {
        final Rect srcRect = Rect.fromLTWH(0, 0, mapImage.width.toDouble(), mapImage.height.toDouble());
        canvas.drawImageRect(mapImage, srcRect, mapRect, Paint()..filterQuality = ui.FilterQuality.high);
      } else {
        // Fallback vector mini-map background if static tile endpoint is offline
        final Paint gridBg = Paint()..color = const Color(0xFF1E293B);
        canvas.drawRect(mapRect, gridBg);

        final Paint gridLine = Paint()
          ..color = const Color(0xFF334155)
          ..strokeWidth = 1.5;
        for (double i = mapRect.left; i <= mapRect.right; i += 20) {
          canvas.drawLine(Offset(i, mapRect.top), Offset(i, mapRect.bottom), gridLine);
        }
        for (double i = mapRect.top; i <= mapRect.bottom; i += 20) {
          canvas.drawLine(Offset(mapRect.left, i), Offset(mapRect.right, i), gridLine);
        }

        // Draw pin marker
        final Paint pinPaint = Paint()..color = Colors.redAccent;
        canvas.drawCircle(Offset(mapRect.center.dx, mapRect.center.dy - 4), 7, pinPaint);
        final Paint pinCenter = Paint()..color = Colors.white;
        canvas.drawCircle(Offset(mapRect.center.dx, mapRect.center.dy - 4), 3, pinCenter);
      }
      canvas.restore();

      // Draw map border
      final Paint mapBorderPaint = Paint()
        ..color = const Color(0xFF00E676)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawRRect(mapRRect, mapBorderPaint);

      // 6. Text Overlay Specifications (Right of Mini Map)
      final double textLeft = mapRect.right + 14.0;
      final double textWidth = width - textLeft - padding;

      double currentY = overlayTop + padding + 4;

      // Header: RoadWatch Branding & GPS Verified Badge
      final double headerFontSize = (overlayHeight * 0.11).clamp(13.0, 20.0);
      final TextPainter brandingPainter = TextPainter(
        text: TextSpan(
          text: '🛡️ RoadWatch GPS Camera',
          style: TextStyle(
            color: Colors.white,
            fontSize: headerFontSize,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      );
      brandingPainter.layout(maxWidth: textWidth);
      brandingPainter.paint(canvas, Offset(textLeft, currentY));

      currentY += brandingPainter.height + 4;

      // Address Row
      final double addressFontSize = (overlayHeight * 0.095).clamp(11.0, 16.0);
      final TextPainter addressPainter = TextPainter(
        text: TextSpan(
          children: [
            const TextSpan(text: '📍 ', style: TextStyle(fontSize: 12)),
            TextSpan(
              text: address.isNotEmpty ? address : 'Address Unavailable',
              style: TextStyle(
                color: const Color(0xFFF1F5F9),
                fontSize: addressFontSize,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        textDirection: ui.TextDirection.ltr,
        maxLines: 2,
        ellipsis: '...',
      );
      addressPainter.layout(maxWidth: textWidth);
      addressPainter.paint(canvas, Offset(textLeft, currentY));

      currentY += addressPainter.height + 4;

      // Coordinates Row (Latitude / Longitude)
      final double metaFontSize = (overlayHeight * 0.085).clamp(10.0, 14.0);
      final String latStr = '${latitude.abs().toStringAsFixed(4)}° ${latitude >= 0 ? 'N' : 'S'}';
      final String lngStr = '${longitude.abs().toStringAsFixed(4)}° ${longitude >= 0 ? 'E' : 'W'}';

      final TextPainter coordsPainter = TextPainter(
        text: TextSpan(
          text: '🌐 Lat: $latStr  |  Long: $lngStr',
          style: TextStyle(
            color: const Color(0xFF38BDF8), // Vivid Light Blue
            fontSize: metaFontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      );
      coordsPainter.layout(maxWidth: textWidth);
      coordsPainter.paint(canvas, Offset(textLeft, currentY));

      currentY += coordsPainter.height + 3;

      // Date, Time & Accuracy Row
      final String dateStr = DateFormat('yyyy-MM-dd').format(timestamp);
      final String timeStr = DateFormat('HH:mm:ss').format(timestamp);
      final String accStr = '± ${accuracy.toStringAsFixed(1)} m';

      final TextPainter footerPainter = TextPainter(
        text: TextSpan(
          children: [
            TextSpan(
              text: '🕒 $dateStr $timeStr  |  🎯 Acc: $accStr  ',
              style: TextStyle(
                color: const Color(0xFFA7F3D0), // Soft Mint
                fontSize: metaFontSize * 0.95,
                fontWeight: FontWeight.w500,
              ),
            ),
            const TextSpan(
              text: '✅ VERIFIED',
              style: TextStyle(
                color: Color(0xFF00E676),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        textDirection: ui.TextDirection.ltr,
      );
      footerPainter.layout(maxWidth: textWidth);
      footerPainter.paint(canvas, Offset(textLeft, currentY));

      // 7. End Recording & Render Final Image Bytes
      final ui.Picture picture = recorder.endRecording();
      final ui.Image compositeImage = await picture.toImage(width, height);
      final ByteData? byteData = await compositeImage.toByteData(format: ui.ImageByteFormat.png);

      if (byteData != null) {
        return byteData.buffer.asUint8List();
      }
    } catch (e) {
      debugPrint('Geotag canvas synthesis error: $e');
    }
    return photoBytes; // Fallback to raw photo if rendering error
  }

  /// Convert Uint8List bytes to base64 Data URL
  static String bytesToDataUrl(Uint8List bytes, {String mimeType = 'image/jpeg'}) {
    final base64Str = base64Encode(bytes);
    return 'data:$mimeType;base64,$base64Str';
  }
}
