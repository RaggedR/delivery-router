import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/saved_address.dart';
import '../models/delivery_location.dart';

class AddressBook {
  static const _key = 'address_book';

  static Future<List<SavedAddress>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_key);
    if (json == null) return [];
    final list = jsonDecode(json) as List;
    return list
        .map((s) => SavedAddress.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  static Future<void> save(String name, DeliveryLocation location) async {
    final addresses = await load();
    // Remove existing entry with same address to avoid duplicates
    addresses.removeWhere((a) => a.location.address == location.address);
    addresses.insert(0, SavedAddress(name: name, location: location));
    await _persist(addresses);
  }

  static Future<void> delete(String address) async {
    final addresses = await load();
    addresses.removeWhere((a) => a.location.address == address);
    await _persist(addresses);
  }

  static Future<void> _persist(List<SavedAddress> addresses) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(addresses.map((a) => a.toJson()).toList()),
    );
  }
}
