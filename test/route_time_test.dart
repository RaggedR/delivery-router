import 'package:flutter_test/flutter_test.dart';
import 'package:delivery_router/providers/route_provider.dart';

void main() {
  group('computeArrivalMinutes', () {
    test('basic two-stop route with stop duration', () {
      // Depart 8:00 (480) + 5 leeway = 485
      // Leg 0: 1200s = 20 min → arrive stop 1 at 505, spend 10 min → leave 515
      // Leg 1: 900s = 15 min → arrive stop 2 at 530, spend 10 min → leave 540
      final arrivals = RouteProvider.computeArrivalMinutes(
        480,
        [1200, 900, 600],
        2,
      );
      expect(arrivals, [505, 530]);
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

    test('zero leeway and zero stop duration', () {
      final arrivals = RouteProvider.computeArrivalMinutes(
        480,
        [1200, 900, 600],
        2,
        leeway: 0,
        stopDuration: 0,
      );
      expect(arrivals, [500, 515]);
    });

    test('stop duration adds up across multiple stops', () {
      // 0 + 0 leeway + 10 min drive → arrive 10, spend 10 → leave 20
      // 20 + 10 min drive → arrive 30, spend 10 → leave 40
      // 40 + 10 min drive → arrive 50
      final arrivals = RouteProvider.computeArrivalMinutes(
        0,
        [600, 600, 600, 600],
        3,
        leeway: 0,
      );
      expect(arrivals, [10, 30, 50]);
    });
  });

  group('computeReturnMinutes', () {
    test('includes stop duration at each delivery stop', () {
      // 480 + 5 + 20 + 10(stop) + 15 + 10(stop) + 10 = 550
      final ret = RouteProvider.computeReturnMinutes(
        480,
        [1200, 900, 600],
      );
      expect(ret, 550);
    });

    test('single leg (depot to depot, no stops)', () {
      // 480 + 5 + 10 = 495 (no stop duration — just driving there and back)
      final ret = RouteProvider.computeReturnMinutes(480, [600]);
      expect(ret, 495);
    });

    test('zero stop duration', () {
      // 480 + 5 + 20 + 15 + 10 = 530
      final ret = RouteProvider.computeReturnMinutes(
        480,
        [1200, 900, 600],
        stopDuration: 0,
      );
      expect(ret, 530);
    });
  });

  group('computeLateIndices', () {
    test('flags stop past effective deadline', () {
      // Arrivals: [505, 530]
      // Stop 0: deadline 510, effective 510-5=505, 505 > 505 → false
      // Stop 1: deadline 525, effective 525-5=520, 530 > 520 → true
      final late = RouteProvider.computeLateIndices(
        [505, 530],
        {0: 510, 1: 525},
      );
      expect(late, {1});
    });

    test('no deadlines set returns empty', () {
      final late = RouteProvider.computeLateIndices([505, 530], {});
      expect(late, <int>{});
    });

    test('exactly at effective deadline is not late', () {
      final late = RouteProvider.computeLateIndices([505], {0: 510});
      expect(late, <int>{});
    });

    test('one minute over is late', () {
      final late = RouteProvider.computeLateIndices([506], {0: 510});
      expect(late, {0});
    });

    test('zero leeway checks against raw deadline', () {
      final late = RouteProvider.computeLateIndices(
        [505, 530],
        {0: 504, 1: 530},
        leeway: 0,
      );
      expect(late, {0});
    });

    test('partial deadlines only check set stops', () {
      final late = RouteProvider.computeLateIndices(
        [505, 530],
        {1: 520},
      );
      // 530 > 520-5=515 → true
      expect(late, {1});
    });
  });

  group('arrival and late check use consistent time base', () {
    test('displayed arrival matches late-check arrival', () {
      const start = 480;
      const legs = [1200, 900, 600];
      const stopCount = 2;

      final arrivals = RouteProvider.computeArrivalMinutes(
        start, legs, stopCount,
      );
      // arrivals = [505, 530]

      // Stop 0 deadline 510, effective 505. Arrival 505 → NOT late.
      final lateSet = RouteProvider.computeLateIndices(
        arrivals,
        {0: 510},
      );
      expect(lateSet, <int>{});

      // Stop 0 deadline 509, effective 504. Arrival 505 > 504 → LATE.
      final lateSet2 = RouteProvider.computeLateIndices(
        arrivals,
        {0: 509},
      );
      expect(lateSet2, {0});
    });
  });
}
