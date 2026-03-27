import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import '../models/delivery_location.dart';

/// Opens Google Maps with the optimized route for turn-by-turn navigation.
class NavigationLauncher {
  static Future<bool> launchRoute({
    required DeliveryLocation depot,
    required List<DeliveryLocation> orderedStops,
  }) async {
    if (orderedStops.isEmpty) return false;

    // Use the Maps URLs API format with addresses for labeled waypoint pins.
    final origin = Uri.encodeComponent(depot.address);
    final destination = Uri.encodeComponent(depot.address);
    final waypoints = orderedStops
        .map((s) => Uri.encodeComponent(s.address))
        .join('%7C'); // pipe-separated

    final url = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&origin=$origin'
      '&destination=$destination'
      '&waypoints=$waypoints'
      '&travelmode=driving',
    );

    if (await canLaunchUrl(url)) {
      return launchUrl(
        url,
        mode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
      );
    }
    return false;
  }
}
