import 'delivery_location.dart';

class OptimizedRoute {
  /// Stops in optimal order (excludes depot — depot is always start and end).
  final List<DeliveryLocation> orderedStops;

  /// Total driving time in seconds across the full circuit.
  final int totalDurationSeconds;

  /// Total driving distance in meters across the full circuit.
  final int totalDistanceMeters;

  /// The full ordered indices into the original distance matrix
  /// (0 = depot, then delivery indices).
  final List<int> tourIndices;

  const OptimizedRoute({
    required this.orderedStops,
    required this.totalDurationSeconds,
    required this.totalDistanceMeters,
    required this.tourIndices,
  });

  String get formattedDuration {
    final hours = totalDurationSeconds ~/ 3600;
    final minutes = (totalDurationSeconds % 3600) ~/ 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }

  String get formattedDistance {
    final km = totalDistanceMeters / 1000;
    return '${km.toStringAsFixed(1)} km';
  }
}
