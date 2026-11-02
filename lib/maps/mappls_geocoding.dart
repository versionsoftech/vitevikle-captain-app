import 'package:geocoding/geocoding.dart' as geo;
import 'package:mappls_gl/mappls_gl.dart' as m;
import 'package:vite_captain/services/app_config.dart';

/// Address parts in the same shape the screens used from the `geocoding` package.
class Placemark {
  const Placemark({
    this.name,
    this.street,
    this.thoroughfare,
    this.subThoroughfare,
    this.subLocality,
    this.locality,
    this.subAdministrativeArea,
    this.administrativeArea,
    this.postalCode,
    this.country,
    this.isoCountryCode,
    this.formattedAddress,
  });

  final String? name;
  final String? street;
  final String? thoroughfare;
  final String? subThoroughfare;
  final String? subLocality;
  final String? locality;
  final String? subAdministrativeArea;
  final String? administrativeArea;
  final String? postalCode;
  final String? country;
  final String? isoCountryCode;
  final String? formattedAddress;
}

class Location {
  const Location({required this.latitude, required this.longitude, required this.timestamp});

  final double latitude;
  final double longitude;
  final DateTime timestamp;
}

String? _clean(String? value) {
  final v = (value ?? '').trim();
  return v.isEmpty ? null : v;
}

Future<List<Placemark>> placemarkFromCoordinates(double latitude, double longitude) async {
  if (AppConfig.useGoogleMap) {
    final marks = await geo.placemarkFromCoordinates(latitude, longitude);
    return marks
        .map(
          (p) => Placemark(
            name: _clean(p.name),
            street: _clean(p.street),
            thoroughfare: _clean(p.thoroughfare),
            subThoroughfare: _clean(p.subThoroughfare),
            subLocality: _clean(p.subLocality),
            locality: _clean(p.locality),
            subAdministrativeArea: _clean(p.subAdministrativeArea),
            administrativeArea: _clean(p.administrativeArea),
            postalCode: _clean(p.postalCode),
            country: _clean(p.country),
            isoCountryCode: _clean(p.isoCountryCode),
          ),
        )
        .toList(growable: false);
  }

  final response = await m.MapplsReverseGeocode(location: m.LatLng(latitude, longitude)).callReverseGeocode();
  final results = response?.results ?? const <m.ReverseGeocodePlace>[];
  return results.map((r) {
    final street = _clean([_clean(r.houseNumber), _clean(r.street)].whereType<String>().join(' '));
    return Placemark(
      name: _clean(r.poi) ?? _clean(r.houseName) ?? street,
      street: street,
      thoroughfare: _clean(r.street),
      subThoroughfare: _clean(r.houseNumber),
      subLocality: _clean(r.locality) ?? _clean(r.subLocality) ?? _clean(r.subSubLocality) ?? _clean(r.village),
      locality: _clean(r.city) ?? _clean(r.district) ?? _clean(r.village),
      subAdministrativeArea: _clean(r.district),
      administrativeArea: _clean(r.state),
      postalCode: _clean(r.pincode),
      country: _clean(r.area) ?? 'India',
      isoCountryCode: 'IN',
      formattedAddress: _clean(r.formattedAddress),
    );
  }).toList(growable: false);
}

Future<List<Location>> locationFromAddress(String address) async {
  final query = address.trim();
  if (query.isEmpty) return const <Location>[];
  final now = DateTime.now();

  if (AppConfig.useGoogleMap) {
    final marks = await geo.locationFromAddress(query);
    return marks
        .map((l) => Location(latitude: l.latitude, longitude: l.longitude, timestamp: now))
        .toList(growable: false);
  }

  final response = await m.MapplsGeoCoding(address: query, itemCount: 1).callGeocoding();
  return (response?.results ?? const <m.GeoCodeResult>[])
      .where((r) => r.latitude != null && r.longitude != null)
      .map((r) => Location(latitude: r.latitude!, longitude: r.longitude!, timestamp: now))
      .toList(growable: false);
}
