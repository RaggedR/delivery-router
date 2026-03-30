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
  static const _stopDurationMinutes = 10;
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
      var orderedStops = <DeliveryLocation>[];
      for (final idx in result.tour) {
        if (idx == 0) continue; // skip depot
        orderedStops.add(allLocations[idx]);
      }

      // Repair for deadline violations: if the shortest route misses
      // deadlines, reorder to visit deadline stops earliest-first and
      // insert non-deadline stops at cheapest positions.
      if (_startTime != null && _deadlines.isNotEmpty) {
        orderedStops = _repairForDeadlines(
          orderedStops, allLocations, matrix.durations,
        );
      }

      // Build tour indices and leg durations from the (possibly repaired) order.
      final tour = [0];
      for (final stop in orderedStops) {
        tour.add(allLocations.indexOf(stop));
      }
      tour.add(0);

      var totalDistance = 0;
      final legDurations = <int>[];
      for (var i = 0; i < tour.length - 1; i++) {
        totalDistance +=
            matrix.distances[tour[i]][tour[i + 1]];
        legDurations.add(
            matrix.durations[tour[i]][tour[i + 1]]);
      }

      _optimizedRoute = OptimizedRoute(
        orderedStops: orderedStops,
        totalDurationSeconds: legDurations.fold(0, (a, b) => a + b),
        totalDistanceMeters: totalDistance,
        tourIndices: tour,
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

  /// Reorders stops to fix deadline violations. Deadline stops are sorted
  /// earliest-first; non-deadline stops are inserted at cheapest positions.
  /// Returns the original order if no violations exist.
  List<DeliveryLocation> _repairForDeadlines(
    List<DeliveryLocation> orderedStops,
    List<DeliveryLocation> allLocations,
    List<List<int>> durations,
  ) {
    final startMin = _startTime!.hour * 60 + _startTime!.minute;

    // Check for violations in current order
    final tour = [0, ...orderedStops.map((s) => allLocations.indexOf(s)), 0];
    final legs = <int>[];
    for (var i = 0; i < tour.length - 1; i++) {
      legs.add(durations[tour[i]][tour[i + 1]]);
    }
    final arrivals = computeArrivalMinutes(
      startMin, legs, orderedStops.length,
    );

    bool hasViolation = false;
    for (var i = 0; i < orderedStops.length; i++) {
      final dl = _deadlines[orderedStops[i].id];
      if (dl != null) {
        final dlMin = dl.hour * 60 + dl.minute;
        if (arrivals[i] > dlMin - _leewayMinutes) {
          hasViolation = true;
          break;
        }
      }
    }
    if (!hasViolation) return orderedStops;

    // Split into deadline and non-deadline stops
    final withDl = orderedStops
        .where((s) => _deadlines.containsKey(s.id))
        .toList();
    final withoutDl = orderedStops
        .where((s) => !_deadlines.containsKey(s.id))
        .toList();

    // Sort deadline stops by deadline time (earliest first)
    withDl.sort((a, b) {
      final da = _deadlines[a.id]!;
      final db = _deadlines[b.id]!;
      return (da.hour * 60 + da.minute).compareTo(db.hour * 60 + db.minute);
    });

    // Start with deadline stops in deadline order
    final repaired = List<DeliveryLocation>.from(withDl);

    // Insert each non-deadline stop at the cheapest position
    for (final free in withoutDl) {
      final freeIdx = allLocations.indexOf(free);
      int bestPos = repaired.length;
      int bestExtra = _insertionCost(
        repaired, bestPos, freeIdx, allLocations, durations,
      );

      for (var pos = 0; pos < repaired.length; pos++) {
        final extra = _insertionCost(
          repaired, pos, freeIdx, allLocations, durations,
        );
        if (extra < bestExtra) {
          bestExtra = extra;
          bestPos = pos;
        }
      }
      repaired.insert(bestPos, free);
    }

    return repaired;
  }

  /// Extra travel time (seconds) from inserting [nodeIdx] at [pos] in the route.
  int _insertionCost(
    List<DeliveryLocation> route,
    int pos,
    int nodeIdx,
    List<DeliveryLocation> allLocations,
    List<List<int>> durations,
  ) {
    final prevIdx = pos == 0
        ? 0 // depot
        : allLocations.indexOf(route[pos - 1]);
    final nextIdx = pos >= route.length
        ? 0 // depot (return)
        : allLocations.indexOf(route[pos]);

    final added = durations[prevIdx][nodeIdx] + durations[nodeIdx][nextIdx];
    final removed = durations[prevIdx][nextIdx];
    return added - removed;
  }

  // --- Static computation helpers (pure functions, testable without Material) ---

  /// Cumulative arrival minutes at each stop, with [leeway] added to departure
  /// and [stopDuration] minutes spent at each stop before driving to the next.
  static List<int> computeArrivalMinutes(
    int startMinutes,
    List<int> legDurationSeconds,
    int stopCount, {
    int leeway = _leewayMinutes,
    int stopDuration = _stopDurationMinutes,
  }) {
    final arrivals = <int>[];
    var current = startMinutes + leeway;
    for (var i = 0; i < stopCount; i++) {
      current += (legDurationSeconds[i] / 60).ceil();
      arrivals.add(current);
      current += stopDuration; // time spent at this stop before next leg
    }
    return arrivals;
  }

  /// Total minutes from departure to return at depot (all legs + stop time).
  static int computeReturnMinutes(
    int startMinutes,
    List<int> legDurationSeconds, {
    int leeway = _leewayMinutes,
    int stopDuration = _stopDurationMinutes,
  }) {
    var current = startMinutes + leeway;
    for (var i = 0; i < legDurationSeconds.length; i++) {
      current += (legDurationSeconds[i] / 60).ceil();
      // Add stop time at each delivery stop (not the final return to depot)
      if (i < legDurationSeconds.length - 1) {
        current += stopDuration;
      }
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
