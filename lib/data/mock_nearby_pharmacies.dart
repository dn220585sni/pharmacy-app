import '../models/nearby_pharmacy.dart';

/// Mock list of nearby pharmacies returned by the availability service.
/// In production this comes from a real-time stock-check API.
const List<NearbyPharmacy> mockNearbyPharmacies = [
  NearbyPharmacy(
    id: 'ph-1',
    name: 'АНЦ',
    address: 'вул. Іванова, 62',
    stockQty: 4,
    distance: '350 м',
    workingHours: '08:00–21:00',
    price: 142.50,
  ),
  NearbyPharmacy(
    id: 'ph-2',
    name: 'Копійка',
    address: 'вул. Петрова, 15',
    stockQty: 2,
    distance: '600 м',
    workingHours: '08:00–22:00',
    price: 142.50,
  ),
  NearbyPharmacy(
    id: 'ph-3',
    name: 'Шара',
    address: 'вул. Сидорова, 21',
    stockQty: 7,
    distance: '1.2 км',
    workingHours: 'цілодобово',
    price: 142.50,
  ),
  NearbyPharmacy(
    id: 'ph-4',
    name: 'Аптека Доброго Дня',
    address: 'просп. Незалежності, 44',
    stockQty: 1,
    distance: '1.8 км',
    workingHours: '09:00–20:00',
    price: 142.50,
  ),
];
