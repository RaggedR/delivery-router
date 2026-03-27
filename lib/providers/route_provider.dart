import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/delivery_location.dart';
import '../models/optimized_route.dart';
import '../services/maps_api_service.dart';
import '../services/tsp_solver.dart';

class RouteProvider extends ChangeNotifier {
  final MapsApiService _mapsApi = MapsApiService();

  DeliveryLocation? _depot;
  final List<DeliveryLocation> _stops = [];
  OptimizedRoute? _optimizedRoute;
  bool _isOptimizing = false;
  String? _error;

  DeliveryLocation? get depot => _depot;
  List<DeliveryLocation> get stops => List.unmodifiable(_stops);
  OptimizedRoute? get optimizedRoute => _optimizedRoute;
  bool get isOptimizing => _isOptimizing;
  String? get error => _error;
  bool get canOptimize => _depot != null && _stops.isNotEmpty && !_isOptimizing;

  static const _depotKey = 'depot';
  static const _stopsKey = 'stops';

  /// Loads the persisted depot and stops from shared preferences.
  Future<void> loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    final depotJson = prefs.getString(_depotKey);
    if (depotJson != null) {
      _depot = DeliveryLocation.fromJson(
        jsonDecode(depotJson) as Map<String, dynamic>,
      );
    }
    final stopsJson = prefs.getString(_stopsKey);
    if (stopsJson != null) {
      final list = jsonDecode(stopsJson) as List;
      _stops.clear();
      _stops.addAll(list.map((s) =>
          DeliveryLocation.fromJson(s as Map<String, dynamic>)));
    }
    notifyListeners();
  }

  Future<void> _saveStops() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _stopsKey,
      jsonEncode(_stops.map((s) => s.toJson()).toList()),
    );
  }

  /// Sets (and persists) the depot/warehouse location.
  Future<void> setDepot(DeliveryLocation location) async {
    _depot = location;
    _optimizedRoute = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_depotKey, jsonEncode(location.toJson()));
    notifyListeners();
  }

  void addStop(DeliveryLocation location) {
    if (_stops.length >= 20) return;
    _stops.add(location);
    _optimizedRoute = null;
    _saveStops();
    notifyListeners();
  }

  void removeStop(String id) {
    _stops.removeWhere((s) => s.id == id);
    _optimizedRoute = null;
    _saveStops();
    notifyListeners();
  }

  void reorderStops(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final item = _stops.removeAt(oldIndex);
    _stops.insert(newIndex, item);
    _optimizedRoute = null;
    _saveStops();
    notifyListeners();
  }

  void clearStops() {
    _stops.clear();
    _optimizedRoute = null;
    _saveStops();
    notifyListeners();
  }

  /// Fetches the distance matrix from Google and solves TSP.
  Future<void> optimizeRoute() async {
    if (_depot == null || _stops.isEmpty) return;

    _isOptimizing = true;
    _error = null;
    _optimizedRoute = null;
    notifyListeners();

    try {
      // Build the full list: depot at index 0, then stops.
      final allLocations = [_depot!, ..._stops];

      // Fetch real driving durations from Google.
      final matrix = await _mapsApi.getDistanceMatrix(allLocations);

      // Solve TSP using Held-Karp on the duration matrix.
      final result = TspSolver.solve(matrix.durations);

      // Map tour indices back to delivery locations (skip depot at start/end).
      final orderedStops = <DeliveryLocation>[];
      for (final idx in result.tour) {
        if (idx == 0) continue; // skip depot
        orderedStops.add(allLocations[idx]);
      }
      // Remove duplicate (last depot) — orderedStops only has stops.
      // The tour is [0, a, b, c, 0] — we just skipped all 0s above.

      // Calculate total distance by summing the tour edges.
      var totalDistance = 0;
      for (var i = 0; i < result.tour.length - 1; i++) {
        totalDistance +=
            matrix.distances[result.tour[i]][result.tour[i + 1]];
      }

      _optimizedRoute = OptimizedRoute(
        orderedStops: orderedStops,
        totalDurationSeconds: result.totalCost,
        totalDistanceMeters: totalDistance,
        tourIndices: result.tour,
      );
    } on MapsApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Optimization failed: $e';
    } finally {
      _isOptimizing = false;
      notifyListeners();
    }
  }
}
