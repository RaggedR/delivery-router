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

  static const _leewayMinutes = 5;
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

  // --- Static computation helpers (pure functions, testable without Material) ---

  /// Cumulative arrival minutes at each stop, with [leeway] added to departure.
  static List<int> computeArrivalMinutes(
    int startMinutes,
    List<int> legDurationSeconds,
    int stopCount, {
    int leeway = _leewayMinutes,
  }) {
    final arrivals = <int>[];
    var current = startMinutes + leeway;
    for (var i = 0; i < stopCount; i++) {
      current += (legDurationSeconds[i] / 60).ceil();
      arrivals.add(current);
    }
    return arrivals;
  }

  /// Total minutes from departure to return at depot (all legs summed).
  static int computeReturnMinutes(
    int startMinutes,
    List<int> legDurationSeconds, {
    int leeway = _leewayMinutes,
  }) {
    var current = startMinutes + leeway;
    for (final sec in legDurationSeconds) {
      current += (sec / 60).ceil();
    }
    return current;
  }

  /// Indices of stops whose arrival exceeds (deadline - [leeway]).
  static Set<int> computeLateIndices(
    List<int> arrivalMinutes,
    Map<int, int> deadlineMinutesByIndex, {
    int leeway = _leewayMinutes,
  }) {
    final lateSet = <int>{};
    for (var i = 0; i < arrivalMinutes.length; i++) {
      final deadline = deadlineMinutesByIndex[i];
      if (deadline != null && arrivalMinutes[i] > deadline - leeway) {
        lateSet.add(i);
      }
    }
    return lateSet;
  }

  // --- Instance methods (delegate to statics, convert to TimeOfDay for UI) ---

  /// Arrival times at each ordered stop (includes leeway departure buffer).
  List<TimeOfDay>? getArrivalTimes() {
    if (_startTime == null || _optimizedRoute == null) return null;
    final startMinutes = _startTime!.hour * 60 + _startTime!.minute;
    final minutes = computeArrivalMinutes(
      startMinutes,
      _optimizedRoute!.legDurationSeconds,
      _optimizedRoute!.orderedStops.length,
    );
    return minutes
        .map((m) => TimeOfDay(hour: (m ~/ 60) % 24, minute: m % 60))
        .toList();
  }

  /// Stop IDs that will miss their deadline (leeway on both ends).
  Set<String> getLateStopIds() {
    if (_startTime == null || _optimizedRoute == null) return {};
    final startMinutes = _startTime!.hour * 60 + _startTime!.minute;
    final arrivals = computeArrivalMinutes(
      startMinutes,
      _optimizedRoute!.legDurationSeconds,
      _optimizedRoute!.orderedStops.length,
    );
    final deadlinesByIndex = <int, int>{};
    for (var i = 0; i < _optimizedRoute!.orderedStops.length; i++) {
      final stop = _optimizedRoute!.orderedStops[i];
      final deadline = _deadlines[stop.id];
      if (deadline != null) {
        deadlinesByIndex[i] = deadline.hour * 60 + deadline.minute;
      }
    }
    final lateIndices = computeLateIndices(arrivals, deadlinesByIndex);
    return lateIndices
        .map((i) => _optimizedRoute!.orderedStops[i].id)
        .toSet();
  }

  /// Estimated return time to depot (includes leeway departure buffer).
  TimeOfDay? getReturnTime() {
    if (_startTime == null || _optimizedRoute == null) return null;
    final startMinutes = _startTime!.hour * 60 + _startTime!.minute;
    final m = computeReturnMinutes(
      startMinutes,
      _optimizedRoute!.legDurationSeconds,
    );
    return TimeOfDay(hour: (m ~/ 60) % 24, minute: m % 60);
  }
}
