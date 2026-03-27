import 'delivery_location.dart';

class SavedAddress {
  final String name;
  final DeliveryLocation location;

  const SavedAddress({required this.name, required this.location});

  Map<String, dynamic> toJson() => {
        'name': name,
        'location': location.toJson(),
      };

  factory SavedAddress.fromJson(Map<String, dynamic> json) {
    return SavedAddress(
      name: json['name'] as String,
      location: DeliveryLocation.fromJson(
        json['location'] as Map<String, dynamic>,
      ),
    );
  }
}
