import 'package:uuid/uuid.dart';

class DeliveryLocation {
  final String id;
  final String address;
  final double lat;
  final double lng;

  DeliveryLocation({
    String? id,
    required this.address,
    required this.lat,
    required this.lng,
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toJson() => {
        'id': id,
        'address': address,
        'lat': lat,
        'lng': lng,
      };

  factory DeliveryLocation.fromJson(Map<String, dynamic> json) {
    return DeliveryLocation(
      id: json['id'] as String,
      address: json['address'] as String,
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is DeliveryLocation && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
