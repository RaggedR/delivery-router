import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/delivery_location.dart';

class MapsApiService {
  /// On web, all requests go through the server proxy which injects the API key.
  static const _baseUrl = '/maps-proxy/maps/api';

  /// Fetches the full n x n distance matrix (duration in seconds) between
  /// all locations. The first element should be the depot.
  ///
  /// Returns two matrices: durations[i][j] and distances[i][j].
  Future<({List<List<int>> durations, List<List<int>> distances})>
      getDistanceMatrix(List<DeliveryLocation> locations) async {
    // The Distance Matrix API allows up to 25 origins x 25 destinations per
    // request, and we have at most 13 locations — so one call suffices.
    final origins = locations
        .map((l) => '${l.lat},${l.lng}')
        .join('|');

    final url = Uri.parse(
      '$_baseUrl/distancematrix/json'
      '?origins=$origins'
      '&destinations=$origins'
      '&mode=driving'
      // API key injected server-side by proxy
    );

    final response = await http.get(url);
    if (response.statusCode != 200) {
      throw MapsApiException(
        'Distance Matrix API error: HTTP ${response.statusCode}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['status'] != 'OK') {
      throw MapsApiException(
        'Distance Matrix API error: ${data['status']} — '
        '${data['error_message'] ?? 'unknown'}',
      );
    }

    final rows = data['rows'] as List;
    final n = locations.length;
    final durations = List.generate(n, (_) => List.filled(n, 0));
    final distances = List.generate(n, (_) => List.filled(n, 0));

    for (var i = 0; i < n; i++) {
      final elements = (rows[i] as Map<String, dynamic>)['elements'] as List;
      for (var j = 0; j < n; j++) {
        final element = elements[j] as Map<String, dynamic>;
        if (element['status'] != 'OK') {
          throw MapsApiException(
            'No route from "${locations[i].address}" to "${locations[j].address}"',
          );
        }
        durations[i][j] =
            (element['duration'] as Map<String, dynamic>)['value'] as int;
        distances[i][j] =
            (element['distance'] as Map<String, dynamic>)['value'] as int;
      }
    }

    return (durations: durations, distances: distances);
  }

  /// Searches for places matching [query] using the Places Autocomplete API.
  /// Returns a list of predictions with placeId and description.
  Future<List<PlacePrediction>> autocomplete(String query) async {
    if (query.trim().isEmpty) return [];

    final url = Uri.parse(
      '$_baseUrl/place/autocomplete/json'
      '?input=${Uri.encodeComponent(query)}'
      '&components=country:au'
      '&types=address'
      // API key injected server-side by proxy
    );

    final response = await http.get(url);
    if (response.statusCode != 200) return [];

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['status'] != 'OK' && data['status'] != 'ZERO_RESULTS') return [];

    final predictions = data['predictions'] as List? ?? [];
    return predictions.map((p) {
      final pred = p as Map<String, dynamic>;
      return PlacePrediction(
        placeId: pred['place_id'] as String,
        description: pred['description'] as String,
      );
    }).toList();
  }

  /// Gets the lat/lng for a given [placeId] using the Place Details API.
  Future<DeliveryLocation?> getPlaceDetails(String placeId) async {
    final url = Uri.parse(
      '$_baseUrl/place/details/json'
      '?place_id=$placeId'
      '&fields=geometry,formatted_address'
      // API key injected server-side by proxy
    );

    final response = await http.get(url);
    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['status'] != 'OK') return null;

    final result = data['result'] as Map<String, dynamic>;
    final location =
        (result['geometry'] as Map<String, dynamic>)['location'] as Map<String, dynamic>;

    return DeliveryLocation(
      address: result['formatted_address'] as String,
      lat: (location['lat'] as num).toDouble(),
      lng: (location['lng'] as num).toDouble(),
    );
  }

  /// Fetches a polyline (encoded) for the given ordered waypoints.
  /// Returns the overview polyline string for rendering on the map.
  Future<String?> getDirectionsPolyline({
    required DeliveryLocation origin,
    required DeliveryLocation destination,
    List<DeliveryLocation> waypoints = const [],
  }) async {
    var waypointsParam = '';
    if (waypoints.isNotEmpty) {
      final wp = waypoints.map((w) => '${w.lat},${w.lng}').join('|');
      waypointsParam = '&waypoints=$wp';
    }

    final url = Uri.parse(
      '$_baseUrl/directions/json'
      '?origin=${origin.lat},${origin.lng}'
      '&destination=${destination.lat},${destination.lng}'
      '$waypointsParam'
      '&mode=driving'
      // API key injected server-side by proxy
    );

    final response = await http.get(url);
    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['status'] != 'OK') return null;

    final routes = data['routes'] as List;
    if (routes.isEmpty) return null;

    return (routes[0] as Map<String, dynamic>)['overview_polyline']['points']
        as String;
  }
}

class PlacePrediction {
  final String placeId;
  final String description;

  const PlacePrediction({
    required this.placeId,
    required this.description,
  });
}

class MapsApiException implements Exception {
  final String message;
  const MapsApiException(this.message);

  @override
  String toString() => 'MapsApiException: $message';
}
