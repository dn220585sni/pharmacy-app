import 'dart:math';

/// A nearby pharmacy that may have the requested drug in stock.
/// Data from ProductBrowser API: /products/{slug}/pharmacies
class NearbyPharmacy {
  final String id;            // pharmacy ID (e.g. "230")
  final String name;          // network name (e.g. "АНЦ")
  final String address;       // full address
  final String? city;
  final int stockQty;         // numerator (stock count)
  final String? distance;     // distance from current location
  final String workingHours;  // e.g. "08:00-21:00 без вихід��их"
  final double price;         // price at this pharmacy
  final double? lat;
  final double? lng;
  final String? pictureUrl;   // pharmacy network logo
  final String? status;       // "OPEN", "CLOSED"
  final bool isOpen;
  final double? distanceKm;  // відстань в км (для сортування)

  const NearbyPharmacy({
    required this.id,
    required this.name,
    required this.address,
    this.city,
    required this.stockQty,
    this.distance,
    required this.workingHours,
    required this.price,
    this.lat,
    this.lng,
    this.pictureUrl,
    this.status,
    this.isOpen = true,
    this.distanceKm,
  });

  /// Display line: "Назва, вул. Адреса"
  String get displayAddress => '$name, $address';

  /// Розрахувати відстань від заданих координат (формула Haversine).
  /// Повертає нову копію NearbyPharmacy з заповненим полем distance.
  NearbyPharmacy withDistanceFrom(double fromLat, double fromLng) {
    if (lat == null || lng == null) return this;
    final d = _haversineKm(fromLat, fromLng, lat!, lng!);
    final distStr = d < 1.0
        ? '${(d * 1000).round()} м'
        : '${d.toStringAsFixed(1)} км';
    return NearbyPharmacy(
      id: id, name: name, address: address, city: city,
      stockQty: stockQty, distance: distStr, workingHours: workingHours,
      price: price, lat: lat, lng: lng, pictureUrl: pictureUrl,
      status: status, isOpen: isOpen, distanceKm: d,
    );
  }

  static double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0; // Earth radius in km
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(lat1)) * cos(_rad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  static double _rad(double deg) => deg * pi / 180;

  factory NearbyPharmacy.fromProductBrowserJson(Map<String, dynamic> json) {
    final addr = json['address'] as Map<String, dynamic>? ?? {};
    final scheduleRange = json['scheduleRange'] as List<dynamic>? ?? [];

    return NearbyPharmacy(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      address: addr['name']?.toString() ?? '',
      city: addr['city']?.toString(),
      stockQty: (json['numerator'] as num?)?.toInt() ?? 0,
      workingHours: scheduleRange.isNotEmpty
          ? scheduleRange.first.toString()
          : '',
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      lat: (addr['lat'] as num?)?.toDouble(),
      lng: (addr['lng'] as num?)?.toDouble(),
      pictureUrl: json['picture']?.toString(),
      status: json['status']?.toString(),
      isOpen: json['status']?.toString() == 'OPEN',
    );
  }
}
