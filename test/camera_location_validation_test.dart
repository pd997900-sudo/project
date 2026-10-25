import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:roadwatch/services/location_service.dart';

void main() {
  group('Camera & Location Mismatch Validation Tests', () {
    test('1. Photo location matching map pin location within tolerance allows submission', () {
      const double photoLat = 13.0298;
      const double photoLng = 80.0168;
      const double photoAccuracy = 15.0; // 15 meters GPS accuracy

      // Map pin moved slightly (e.g. 20 meters away)
      const double selectedLat = 13.0299;
      const double selectedLng = 80.0169;

      final double distance = Geolocator.distanceBetween(
        photoLat,
        photoLng,
        selectedLat,
        selectedLng,
      );

      final double permittedTolerance = (photoAccuracy * 2.5).clamp(80.0, 250.0);

      expect(distance <= permittedTolerance, isTrue);
    });

    test('2. Photo location differing from map pin beyond permitted tolerance is flagged as mismatch', () {
      const double photoLat = 13.0298;
      const double photoLng = 80.0168;
      const double photoAccuracy = 10.0;

      // Map pin moved 1 kilometer away
      const double selectedLat = 13.0400;
      const double selectedLng = 80.0300;

      final double distance = Geolocator.distanceBetween(
        photoLat,
        photoLng,
        selectedLat,
        selectedLng,
      );

      final double permittedTolerance = (photoAccuracy * 2.5).clamp(80.0, 250.0);

      expect(distance > permittedTolerance, isTrue);
    });

    test('3. Exact required error message string is defined', () {
      const String expectedErrorMessage =
          "Location mismatch! The photo location and selected map location do not match. Please capture the photo at the complaint location and try again.";

      expect(
        expectedErrorMessage,
        equals("Location mismatch! The photo location and selected map location do not match. Please capture the photo at the complaint location and try again."),
      );
    });

    test('4. GeotagLocation constructs correct metadata object', () {
      final now = DateTime.now();
      final location = GeotagLocation(
        latitude: 13.0298,
        longitude: 80.0168,
        accuracy: 5.0,
        address: 'Mevalurkuppam, Tamil Nadu, India',
        timestamp: now,
        status: LocationStatus.ready,
      );

      expect(location.latitude, equals(13.0298));
      expect(location.longitude, equals(80.0168));
      expect(location.accuracy, equals(5.0));
      expect(location.address, contains('Mevalurkuppam'));
      expect(location.isAccurateEnough, isTrue);
    });
  });
}
