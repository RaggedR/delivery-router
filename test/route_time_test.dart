import 'package:flutter_test/flutter_test.dart';
import 'package:delivery_router/providers/route_provider.dart';

void main() {
  group('computeArrivalMinutes', () {
    test('basic two-stop route', () {
      // Depart 8:00 (480) + 5 leeway = 485
      // Leg 0: 1200s = 20 min → arrive stop 1 at 505
      // Leg 1: 900s = 15 min → arrive stop 2 at 520
      final arrivals = RouteProvider.computeArrivalMinutes(
        480,
        [1200, 900, 600], // 3 legs: 2 stops + return
        2,
      );
      expect(arrivals, [505, 520]);
    });

    test('rounds up partial minutes', () {
      // 90 seconds = 1.5 min → ceil = 2
      final arrivals = RouteProvider.computeArrivalMinutes(
        0,
        [90],
        1,
        leeway: 0,
      );
      expect(arrivals, [2]);
    });

    test('single stop', () {
      // 480 + 5 + ceil(600/60) = 495
      final arrivals = RouteProvider.computeArrivalMinutes(
        480,
        [600, 300],
        1,
      );
      expect(arrivals, [495]);
    });

    test('zero leeway', () {
      final arrivals = RouteProvider.computeArrivalMinutes(
        480,
        [1200, 900, 600],
        2,
        leeway: 0,
      );
      expect(arrivals, [500, 515]);
    });
  });

  group('computeReturnMinutes', () {
    test('sums all legs including return', () {
      // 480 + 5 + 20 + 15 + 10 = 530
      final ret = RouteProvider.computeReturnMinutes(
        480,
        [1200, 900, 600],
      );
      expect(ret, 530);
    });

    test('single leg (depot to depot)', () {
      // 480 + 5 + 10 = 495
      final ret = RouteProvider.computeReturnMinutes(480, [600]);
      expect(ret, 495);
    });
  });

  group('computeLateIndices', () {
    test('flags stop past effective deadline', () {
      // Arrivals: [505, 520]
      // Stop 0: deadline 510, effective 510-5=505, 505 > 505 → false
      // Stop 1: deadline 515, effective 515-5=510, 520 > 510 → true
      final late = RouteProvider.computeLateIndices(
        [505, 520],
        {0: 510, 1: 515},
      );
      expect(late, {1});
    });

    test('no deadlines set returns empty', () {
      final late = RouteProvider.computeLateIndices([505, 520], {});
      expect(late, <int>{});
    });

    test('exactly at effective deadline is not late', () {
      // Arrival 505, deadline 510, effective 510-5=505, 505 > 505 → false
      final late = RouteProvider.computeLateIndices([505], {0: 510});
      expect(late, <int>{});
    });

    test('one minute over is late', () {
      // Arrival 506, deadline 510, effective 505, 506 > 505 → true
      final late = RouteProvider.computeLateIndices([506], {0: 510});
      expect(late, {0});
    });

    test('zero leeway checks against raw deadline', () {
      // Arrival 505, deadline 504 → 505 > 504 → late
      // Arrival 520, deadline 520 → 520 > 520 → false
      final late = RouteProvider.computeLateIndices(
        [505, 520],
        {0: 504, 1: 520},
        leeway: 0,
      );
      expect(late, {0});
    });

    test('partial deadlines only check set stops', () {
      // Only stop index 1 has a deadline
      final late = RouteProvider.computeLateIndices(
        [505, 520],
        {1: 510},
      );
      // 520 > 510-5=505 → true
      expect(late, {1});
    });
  });

  group('arrival and late check use consistent time base', () {
    test('displayed arrival matches late-check arrival', () {
      // This is the core consistency test from the review.
      // Both computeArrivalMinutes and computeLateIndices should use
      // the same arrival values so the UI is never contradictory.
      const start = 480; // 8:00 AM
      const legs = [1200, 900, 600]; // 20, 15, 10 min
      const stopCount = 2;

      final arrivals = RouteProvider.computeArrivalMinutes(
        start, legs, stopCount,
      );

      // If stop 1 deadline is 510 (8:30), effective is 505.
      // Arrival is 505 → NOT late (not >). This should match what the UI shows.
      final lateSet = RouteProvider.computeLateIndices(
        arrivals,
        {0: 510},
      );
      expect(lateSet, <int>{});

      // If deadline is 509, effective is 504. Arrival 505 > 504 → LATE.
      final lateSet2 = RouteProvider.computeLateIndices(
        arrivals,
        {0: 509},
      );
      expect(lateSet2, {0});
    });
  });
}
