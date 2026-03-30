import 'dart:convert';
import 'package:flutter/material.dart';
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
  TimeOfDay? _startTime;
  final Map<String, TimeOfDay> _deadlines = {};

  DeliveryLocation? get depot => _depot;
  List<DeliveryLocation> get stops => List.unmodifiable(_stops);
  OptimizedRoute? get optimizedRoute => _optimizedRoute;
  bool get isOptimizing => _isOptimizing;
  String? get error => _error;
  bool get canOptimize => _depot != null && _stops.isNotEmpty && !_isOptimizing;
  TimeOfDay? get startTime => _startTime;
  TimeOfDay? deadlineFor(String stopId) => _deadlines[stopId];

  static const _depotKey = 'depot';
  static const _stopsKey = 'stops';
  static const _startTimeKey = 'startTime';
  static const _deadlinesKey = 'deadlines';

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
    final startTimeMinutes = prefs.getInt(_startTimeKey);
    if (startTimeMinutes != null) {
      _startTime = TimeOfDay(
        hour: startTimeMinutes ~/ 60,
        minute: startTimeMinutes % 60,
      );
    }
    final deadlinesJson = prefs.getString(_deadlinesKey);
    if (deadlinesJson != null) {
      final map = jsonDecode(deadlinesJson) as Map<String, dynamic>;
      _deadlines.clear();
      for (final entry in map.entries) {
        final mins = entry.value as int;
        _deadlines[entry.key] = TimeOfDay(hour: mins ~/ 60, minute: mins % 60);
      }
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

  Future<void> setStartTime(TimeOfDay? time) async {
    _startTime = time;
    final prefs = await SharedPreferences.getInstance();
    if (time != null) {
      await prefs.setInt(_startTimeKey, time.hour * 60 + time.minute);
    } else {
      await prefs.remove(_startTimeKey);
    }
    notifyListeners();
  }

  Future<void> setDeadline(String stopId, TimeOfDay time) async {
    _deadlines[stopId] = time;
    await _saveDeadlines();
    notifyListeners();
  }

  Future<void> removeDeadline(String stopId) async {
    _deadlines.remove(stopId);
    await _saveDeadlines();
    notifyListeners();
  }

  Future<void> _saveDeadlines() async {
    final prefs = await SharedPreferences.getInstance();
    final map = <String, int>{};
    for (final entry in _deadlines.entries) {
      map[entry.key] = entry.value.hour * 60 + entry.value.minute;
    }
    await prefs.setString(_deadlinesKey, jsonEncode(map));
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
    _deadlines.remove(id);
    _optimizedRoute = null;
    _saveStops();
    _saveDeadlines();
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
    _deadlines.clear();
    _optimizedRoute = null;
    _saveStops();
    _saveDeadlines();
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

      // Calculate total distance and per-leg durations by walking the tour edges.
      var totalDistance = 0;
      final legDurations = <int>[];
      for (var i = 0; i < result.tour.length - 1; i++) {
        totalDistance +=
            matrix.distances[result.tour[i]][result.tour[i + 1]];
        legDurations.add(
            matrix.durations[result.tour[i]][result.tour[i + 1]]);
      }

      _optimizedRoute = OptimizedRoute(
        orderedStops: orderedStops,
        totalDurationSeconds: result.totalCost,
        totalDistanceMeters: totalDistance,
        tourIndices: result.tour,
        legDurationSeconds: legDurations,
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

  /// Nominal arrival times at each ordered stop (no leeway applied).
  /// Returns null if start time or optimized route is not set.
  List<TimeOfDay>? getArrivalTimes() {
    if (_startTime == null || _optimizedRoute == null) return null;
    final arrivals = <TimeOfDay>[];
    var currentMinutes = _startTime!.hour * 60 + _startTime!.minute;
    for (var i = 0; i < _optimizedRoute!.orderedStops.length; i++) {
      currentMinutes += (_optimizedRoute!.legDurationSeconds[i] / 60).ceil();
      arrivals.add(TimeOfDay(
        hour: (currentMinutes ~/ 60) % 24,
        minute: currentMinutes % 60,
      ));
    }
    return arrivals;
  }

  /// Stop IDs that will miss their deadline with hidden 5-minute leeway
  /// applied on both ends (depart 5 min late, arrive 5 min before deadline).
  Set<String> getLateStopIds() {
    if (_startTime == null || _optimizedRoute == null) return {};
    const leewayMinutes = 5;
    final lateIds = <String>{};
    var currentMinutes =
        _startTime!.hour * 60 + _startTime!.minute + leewayMinutes;
    for (var i = 0; i < _optimizedRoute!.orderedStops.length; i++) {
      currentMinutes +=
          (_optimizedRoute!.legDurationSeconds[i] / 60).ceil();
      final stop = _optimizedRoute!.orderedStops[i];
      final deadline = _deadlines[stop.id];
      if (deadline != null) {
        final effectiveDeadline =
            deadline.hour * 60 + deadline.minute - leewayMinutes;
        if (currentMinutes > effectiveDeadline) {
          lateIds.add(stop.id);
        }
      }
    }
    return lateIds;
  }

  /// Estimated return time to the depot (null if no start time or route).
  TimeOfDay? getReturnTime() {
    if (_startTime == null || _optimizedRoute == null) return null;
    var currentMinutes = _startTime!.hour * 60 + _startTime!.minute;
    for (final legSeconds in _optimizedRoute!.legDurationSeconds) {
      currentMinutes += (legSeconds / 60).ceil();
    }
    return TimeOfDay(
      hour: (currentMinutes ~/ 60) % 24,
      minute: currentMinutes % 60,
    );
  }
}
