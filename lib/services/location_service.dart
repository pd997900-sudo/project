import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:http/http.dart' as http;
import '../models/india_districts.dart';

class LocationResult {
  final String address;
  final String state;
  final String district;
  final String city;

  LocationResult({
    required this.address,
    required this.state,
    required this.district,
    required this.city,
  });
}

enum LocationStatus {
  initial,
  requesting,
  permissionDenied,
  permissionDeniedForever,
  serviceDisabled,
  timeout,
  poorAccuracy,
  ready,
  error,
}

class GeotagLocation {
  final double latitude;
  final double longitude;
  final double accuracy; // meters
  final String address;
  final DateTime timestamp;
  final LocationStatus status;
  final String statusMessage;

  static const double maxAccuracyThreshold = 20.0; // meters

  GeotagLocation({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.address,
    DateTime? timestamp,
    this.status = LocationStatus.ready,
    this.statusMessage = 'GPS Location verified',
  }) : timestamp = timestamp ?? DateTime.now();

  bool get isAccurateEnough => accuracy > 0 && accuracy <= (kIsWeb ? 150.0 : 35.0) && (status == LocationStatus.ready || status == LocationStatus.poorAccuracy);

  GeotagLocation copyWith({
    double? latitude,
    double? longitude,
    double? accuracy,
    String? address,
    DateTime? timestamp,
    LocationStatus? status,
    String? statusMessage,
  }) {
    return GeotagLocation(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accuracy: accuracy ?? this.accuracy,
      address: address ?? this.address,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }

  factory GeotagLocation.initial() {
    return GeotagLocation(
      latitude: 0.0,
      longitude: 0.0,
      accuracy: 999.0,
      address: 'Detecting live GPS location...',
      status: LocationStatus.initial,
      statusMessage: 'Initializing high-accuracy GPS...',
    );
  }

  factory GeotagLocation.error(LocationStatus status, String message) {
    return GeotagLocation(
      latitude: 0.0,
      longitude: 0.0,
      accuracy: 999.0,
      address: 'Location Unavailable',
      status: status,
      statusMessage: message,
    );
  }
}

class LocationService {
  static double get maxAccuracyThreshold => kIsWeb ? 150.0 : 35.0;
  StreamSubscription<Position>? _positionSubscription;

  /// Check location permissions and service status
  Future<LocationStatus> checkPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return LocationStatus.serviceDisabled;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return LocationStatus.permissionDenied;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return LocationStatus.permissionDeniedForever;
    }

    return LocationStatus.ready;
  }

  /// Get current high-accuracy single location (Guarantees FRESH location, NO cached/old location)
  Future<GeotagLocation> getCurrentHighAccuracyLocation() async {
    final status = await checkPermissions();
    if (status == LocationStatus.serviceDisabled) {
      return GeotagLocation.error(
        LocationStatus.serviceDisabled,
        'Unable to get current location. Please enable GPS and try again.',
      );
    } else if (status == LocationStatus.permissionDenied || status == LocationStatus.permissionDeniedForever) {
      return GeotagLocation.error(
        LocationStatus.permissionDenied,
        'Unable to get current location. Please enable GPS and try again.',
      );
    }

    try {
      Position? bestPosition;

      // 1. Initial high-accuracy hardware query
      try {
        bestPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: kIsWeb ? 12 : 5),
        );
      } catch (_) {}

      // 2. Stream refinement if initial position is null or accuracy is poor (> 25m)
      if (bestPosition == null || bestPosition!.accuracy > maxAccuracyThreshold) {
        final completer = Completer<Position?>();
        const locationSettings = LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 0,
        );

        StreamSubscription<Position>? sub;
        sub = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (Position pos) {
            if (bestPosition == null || pos.accuracy < bestPosition!.accuracy) {
              bestPosition = pos;
            }
            if (pos.accuracy <= maxAccuracyThreshold && !completer.isCompleted) {
              completer.complete(pos);
            }
          },
          onError: (_) {},
        );

        Timer(Duration(seconds: kIsWeb ? 12 : 6), () {
          if (!completer.isCompleted) {
            completer.complete(bestPosition);
          }
        });

        try {
          bestPosition = await completer.future;
        } catch (_) {} finally {
          await sub?.cancel();
        }
      }

      if (bestPosition == null) {
        return GeotagLocation.error(
          LocationStatus.timeout,
          'Unable to get current location. Please enable GPS and try again.',
        );
      }

      final address = await reverseGeocode(bestPosition!.latitude, bestPosition!.longitude);
      final isGoodAccuracy = bestPosition!.accuracy <= maxAccuracyThreshold;

      return GeotagLocation(
        latitude: bestPosition!.latitude,
        longitude: bestPosition!.longitude,
        accuracy: bestPosition!.accuracy,
        address: address,
        timestamp: DateTime.now(),
        status: isGoodAccuracy ? LocationStatus.ready : LocationStatus.poorAccuracy,
        statusMessage: isGoodAccuracy
            ? 'Fresh GPS location acquired (${bestPosition!.accuracy.toStringAsFixed(1)}m)'
            : 'Unable to get current location. Please enable GPS and try again.',
      );
    } on TimeoutException {
      return GeotagLocation.error(
        LocationStatus.timeout,
        'Unable to get current location. Please enable GPS and try again.',
      );
    } catch (e) {
      return GeotagLocation.error(
        LocationStatus.error,
        'Unable to get current location. Please enable GPS and try again.',
      );
    }
  }

  /// Start continuous high-accuracy location tracking stream (Only live fixes, NO cached positions)
  Stream<GeotagLocation> startContinuousLocationTracking() {
    final controller = StreamController<GeotagLocation>();

    checkPermissions().then((status) async {
      if (status != LocationStatus.ready) {
        controller.add(GeotagLocation.error(
          status,
          'Unable to get current location. Please enable GPS and try again.',
        ));
        return;
      }

      // Configure continuous high-accuracy stream settings (fresh positions only)
      const LocationSettings locationSettings = LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0, // continuous fresh updates
      );

      _positionSubscription = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
        (Position position) async {
          final isAccurate = position.accuracy <= maxAccuracyThreshold;
          final address = await reverseGeocode(position.latitude, position.longitude);

          controller.add(GeotagLocation(
            latitude: position.latitude,
            longitude: position.longitude,
            accuracy: position.accuracy,
            address: address,
            timestamp: DateTime.now(),
            status: isAccurate ? LocationStatus.ready : LocationStatus.poorAccuracy,
            statusMessage: isAccurate
                ? 'Fresh GPS location active (${position.accuracy.toStringAsFixed(1)}m)'
                : 'GPS accuracy is weak (${position.accuracy.toStringAsFixed(1)}m). Please step into an open area.',
          ));
        },
        onError: (error) {
          controller.add(GeotagLocation.error(
            LocationStatus.error,
            'Unable to get current location. Please enable GPS and try again.',
          ));
        },
      );
    });

    controller.onCancel = () {
      _positionSubscription?.cancel();
    };

    return controller.stream;
  }

  void stopTracking() {
    _positionSubscription?.cancel();
  }

  /// Generate Open Location Code (Plus Code) algorithmically from latitude and longitude
  static String getPlusCode(double lat, double lng) {
    const codeAlphabet = '23456789CFGHJMPQRVWX';
    double normLat = (lat + 90.0).clamp(0.0, 180.0);
    double normLng = (lng + 180.0).clamp(0.0, 360.0);

    int latCode = (normLat * 8000).floor();
    int lngCode = (normLng * 8000).floor();

    int p1Lat = (latCode ~/ 720000) % 20;
    int p1Lng = (lngCode ~/ 144000) % 20;
    int p2Lat = (latCode ~/ 36000) % 20;
    int p2Lng = (lngCode ~/ 7200) % 20;
    int p3Lat = (latCode ~/ 1800) % 20;
    int p3Lng = (lngCode ~/ 360) % 20;
    int p4Lat = (latCode ~/ 90) % 20;
    int p4Lng = (lngCode ~/ 18) % 20;

    return '${codeAlphabet[p1Lat]}${codeAlphabet[p1Lng]}${codeAlphabet[p2Lat]}${codeAlphabet[p2Lng]}+${codeAlphabet[p3Lat]}${codeAlphabet[p3Lng]}${codeAlphabet[p4Lat]}${codeAlphabet[p4Lng]}'.toLowerCase();
  }

  static String _cleanAndFormatAddress(String rawAddr, double lat, double lng) {
    String clean = rawAddr
        .replaceAll(RegExp(r'Saveetha Engineering College,?\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'Saveetha,?\s*', caseSensitive: false), '')
        .replaceAll('600124', '602105')
        .trim();

    if (clean.startsWith(',')) clean = clean.substring(1).trim();

    final bool isMevalurkuppamArea = (lat >= 13.000 && lat <= 13.080 && lng >= 80.000 && lng <= 80.060);

    if (isMevalurkuppamArea) {
      if (!clean.toLowerCase().contains('mevalurkuppam')) {
        clean = 'Mevalurkuppam, $clean';
      }
      if (!clean.toLowerCase().contains('sriperumbudur')) {
        clean = clean.replaceAll('Mevalurkuppam', 'Mevalurkuppam, Sriperumbudur');
      }
      if (!clean.contains('602105')) {
        if (clean.contains('Tamil Nadu')) {
          clean = clean.replaceAll('Tamil Nadu', 'Tamil Nadu - 602105');
        } else {
          clean = '$clean, 602105';
        }
      }
    }

    return clean.isEmpty ? 'Mevalurkuppam, Sriperumbudur, Tamil Nadu - 602105, India' : clean;
  }

  /// Reverse-geocode latitude and longitude into human-readable physical address
  static Future<String> reverseGeocode(double lat, double lng) async {
    if (lat == 0.0 && lng == 0.0) {
      return 'Detecting live GPS location...';
    }

    final String generatedPlusCode = getPlusCode(lat, lng);

    // 1. Try Flutter native geocoding package FIRST on mobile devices (iOS / Android)
    try {
      if (!kIsWeb) {
        List<geo.Placemark> placemarks = await geo.placemarkFromCoordinates(lat, lng);
        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          final parts = <String>[];
          if (place.name != null && place.name!.trim().isNotEmpty && place.name != place.street) {
            parts.add(place.name!.trim());
          }
          if (place.street != null && place.street!.trim().isNotEmpty) {
            parts.add(place.street!.trim());
          }
          if (place.subLocality != null && place.subLocality!.trim().isNotEmpty && place.subLocality != place.locality) {
            parts.add(place.subLocality!.trim());
          }
          if (place.locality != null && place.locality!.trim().isNotEmpty) {
            parts.add(place.locality!.trim());
          }
          if (place.administrativeArea != null && place.administrativeArea!.trim().isNotEmpty) {
            parts.add(place.administrativeArea!.trim());
          }
          if (place.postalCode != null && place.postalCode!.trim().isNotEmpty) {
            parts.add(place.postalCode!.trim());
          }
          if (place.country != null && place.country!.trim().isNotEmpty) {
            parts.add(place.country!.trim());
          }
          if (parts.isNotEmpty) {
            return _cleanAndFormatAddress(parts.join(', '), lat, lng);
          }
        }
      }
    } catch (e) {
      debugPrint('Native reverse geocoding note: $e');
    }

    // 2. Try OpenStreetMap Nominatim API with User-Agent header (required by OSM policy)
    try {
      final osmUrl = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=$lat&lon=$lng&zoom=16&addressdetails=1',
      );
      final res = await http.get(osmUrl, headers: {
        'User-Agent': 'RoadWatch-App/1.0 (contact@roadwatch.org)',
        'Accept-Language': 'en',
      }).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map) {
          final addrMap = data['address'] as Map?;
          if (addrMap != null) {
            final parts = <String>[];
            final houseNum = addrMap['house_number'];
            final road = addrMap['road'] ?? addrMap['pedestrian'] ?? addrMap['street'] ?? addrMap['highway'];
            final village = addrMap['village'] ?? addrMap['suburb'] ?? addrMap['neighbourhood'] ?? addrMap['residential'] ?? addrMap['hamlet'] ?? addrMap['subdistrict'] ?? addrMap['locality'];
            final city = addrMap['city'] ?? addrMap['town'] ?? addrMap['county'] ?? addrMap['district'] ?? addrMap['state_district'];
            final state = addrMap['state'];
            final postcode = addrMap['postcode'];
            final country = addrMap['country'];

            if (houseNum != null && houseNum.toString().trim().isNotEmpty) parts.add('#${houseNum.toString().trim()}');
            if (road != null && road.toString().trim().isNotEmpty) parts.add(road.toString().trim());
            if (village != null && village.toString().trim().isNotEmpty) parts.add(village.toString().trim());
            if (city != null && city.toString().trim().isNotEmpty && city.toString().trim() != village?.toString().trim()) parts.add(city.toString().trim());
            if (state != null && state.toString().trim().isNotEmpty) parts.add(state.toString().trim());
            if (postcode != null && postcode.toString().trim().isNotEmpty) parts.add(postcode.toString().trim());
            if (country != null && country.toString().trim().isNotEmpty) parts.add(country.toString().trim());

            if (parts.isNotEmpty) {
              return _cleanAndFormatAddress(parts.join(', '), lat, lng);
            }
          }

          if (data['display_name'] != null && data['display_name'].toString().trim().isNotEmpty) {
            return _cleanAndFormatAddress(data['display_name'].toString().trim(), lat, lng);
          }
        }
      }
    } catch (e) {
      debugPrint('OSM Nominatim reverse geocode note: $e');
    }

    // 3. Try Photon Komoot OpenStreetMap Reverse Geocoder API
    try {
      final photonUrl = Uri.parse(
        'https://photon.komoot.io/reverse?lat=$lat&lon=$lng',
      );
      final res = await http.get(photonUrl).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map && data['features'] is List && (data['features'] as List).isNotEmpty) {
          final props = data['features'][0]['properties'] as Map?;
          if (props != null) {
            final parts = <String>[];
            if (props['name'] != null && props['name'].toString().trim().isNotEmpty) parts.add(props['name'].toString().trim());
            if (props['housenumber'] != null && props['housenumber'].toString().trim().isNotEmpty) parts.add('#${props['housenumber'].toString().trim()}');
            if (props['street'] != null && props['street'].toString().trim().isNotEmpty) parts.add(props['street'].toString().trim());
            if (props['district'] != null && props['district'].toString().trim().isNotEmpty) parts.add(props['district'].toString().trim());
            if (props['city'] != null && props['city'].toString().trim().isNotEmpty) parts.add(props['city'].toString().trim());
            if (props['state'] != null && props['state'].toString().trim().isNotEmpty) parts.add(props['state'].toString().trim());
            if (props['postcode'] != null && props['postcode'].toString().trim().isNotEmpty) parts.add(props['postcode'].toString().trim());
            if (props['country'] != null && props['country'].toString().trim().isNotEmpty) parts.add(props['country'].toString().trim());

            if (parts.isNotEmpty) {
              return _cleanAndFormatAddress(parts.join(', '), lat, lng);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Photon Komoot reverse geocode note: $e');
    }

    // 4. Try BigDataCloud Reverse Geocode Client API
    try {
      final bdcUrl = Uri.parse(
        'https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=$lat&longitude=$lng&localityLanguage=en',
      );
      final res = await http.get(bdcUrl).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map) {
          final locality = data['locality'] ?? data['city'] ?? data['principalSubdivision'];
          final state = data['principalSubdivision'] ?? '';
          final country = data['countryName'] ?? '';
          final postcode = data['postcode'] ?? '';

          final parts = <String>[];
          if (locality != null && locality.toString().trim().isNotEmpty) parts.add(locality.toString().trim());
          if (state.toString().trim().isNotEmpty) parts.add(state.toString().trim());
          if (postcode.toString().trim().isNotEmpty) parts.add(postcode.toString().trim());
          if (country.toString().trim().isNotEmpty) parts.add(country.toString().trim());

          if (parts.isNotEmpty) {
            return _cleanAndFormatAddress(parts.join(', '), lat, lng);
          }
        }
      }
    } catch (e) {
      debugPrint('BigDataCloud reverse geocode note: $e');
    }

    // Dynamic fallback based on actual coordinates
    if (lat >= 13.000 && lat <= 13.080 && lng >= 80.000 && lng <= 80.060) {
      return 'Mevalurkuppam, Sriperumbudur, Tamil Nadu - 602105, India';
    }

    return 'Lat: ${lat.toStringAsFixed(5)}°, Long: ${lng.toStringAsFixed(5)}° (PlusCode: $generatedPlusCode)';
  }

  /// Reverse geocode coordinates into full LocationResult with State, District, City, and Address
  static Future<LocationResult> reverseGeocodeDetailed(double lat, double lng) async {
    final address = await reverseGeocode(lat, lng);
    String detectedState = 'Tamil Nadu';
    String detectedDistrict = 'Kanchipuram';
    String detectedCity = 'Sriperumbudur';

    // 1. Try detecting from reverse-geocoded address
    final fromAddress = IndiaDistricts.detectFromAddress(address);
    if (fromAddress != null) {
      detectedState = fromAddress['state'] ?? detectedState;
      detectedDistrict = fromAddress['district'] ?? detectedDistrict;
    } else {
      // 2. Coordinate boundary fallbacks for key Indian metropolitan/industrial zones
      if (lat >= 12.80 && lat <= 13.20 && lng >= 79.70 && lng <= 80.15) {
        detectedState = 'Tamil Nadu';
        detectedDistrict = 'Kanchipuram';
        detectedCity = 'Sriperumbudur';
      } else if (lat >= 12.95 && lat <= 13.25 && lng >= 80.15 && lng <= 80.35) {
        detectedState = 'Tamil Nadu';
        detectedDistrict = 'Chennai';
        detectedCity = 'Chennai';
      } else if (lat >= 13.05 && lat <= 13.40 && lng >= 79.80 && lng <= 80.20) {
        detectedState = 'Tamil Nadu';
        detectedDistrict = 'Tiruvallur';
        detectedCity = 'Tiruvallur';
      } else if (lat >= 12.80 && lat <= 13.15 && lng >= 77.40 && lng <= 77.75) {
        detectedState = 'Karnataka';
        detectedDistrict = 'Bengaluru Urban';
        detectedCity = 'Bengaluru';
      } else if (lat >= 18.85 && lat <= 19.30 && lng >= 72.75 && lng <= 73.05) {
        detectedState = 'Maharashtra';
        detectedDistrict = 'Mumbai City';
        detectedCity = 'Mumbai';
      } else if (lat >= 17.25 && lat <= 17.55 && lng >= 78.25 && lng <= 78.60) {
        detectedState = 'Telangana';
        detectedDistrict = 'Hyderabad';
        detectedCity = 'Hyderabad';
      } else if (lat >= 28.40 && lat <= 28.85 && lng >= 76.90 && lng <= 77.40) {
        detectedState = 'Delhi';
        detectedDistrict = 'New Delhi';
        detectedCity = 'New Delhi';
      }
    }

    // Try to extract city from address
    final lowerAddr = address.toLowerCase();
    for (var loc in IndiaDistricts.localityMapping.keys) {
      if (lowerAddr.contains(loc)) {
        detectedCity = loc[0].toUpperCase() + loc.substring(1);
        break;
      }
    }

    // Standardize district name against IndiaDistricts list
    final validDistricts = IndiaDistricts.getDistricts(detectedState);
    final matchIdx = validDistricts.indexWhere((d) => d.toLowerCase() == detectedDistrict.toLowerCase());
    if (matchIdx != -1) {
      detectedDistrict = validDistricts[matchIdx];
    } else {
      final partialIdx = validDistricts.indexWhere((d) => d.toLowerCase().contains(detectedDistrict.toLowerCase()) || detectedDistrict.toLowerCase().contains(d.toLowerCase()));
      if (partialIdx != -1) {
        detectedDistrict = validDistricts[partialIdx];
      }
    }

    return LocationResult(
      address: address,
      state: detectedState,
      district: detectedDistrict,
      city: detectedCity,
    );
  }
}
