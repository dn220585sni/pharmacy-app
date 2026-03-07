/// A nearby pharmacy that may have the requested drug in stock.
class NearbyPharmacy {
  final String id;
  final String name;
  final String address;
  final int stockQty;
  final String? distance;

  /// Working hours, e.g. "08:00–21:00" or "цілодобово".
  final String workingHours;

  /// Price of the drug at this pharmacy.
  final double price;

  const NearbyPharmacy({
    required this.id,
    required this.name,
    required this.address,
    required this.stockQty,
    this.distance,
    required this.workingHours,
    required this.price,
  });

  /// Display line: "Назва, вул. Адреса"
  String get displayAddress => '$name, $address';
}
