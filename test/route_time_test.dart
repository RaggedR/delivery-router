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

  group('repairStopOrder', () {
    // Simple 4-node graph: 0=depot, 1,2,3=stops
    // All edges 600s (10 min) for simplicity.
    final durations = [
      [0, 600, 600, 600],
      [600, 0, 600, 600],
      [600, 600, 0, 600],
      [600, 600, 600, 0],
    ];

    test('returns original order when no violations', () {
      // Depart 480 + 5 leeway = 485. Stop 1 arrive 495, stop 2 arrive 515.
      // Deadline at node 1: 500 → effective 495. 495 > 495 → false. No violation.
      final result = RouteProvider.repairStopOrder(
        stopIndices: [1, 2],
        durations: durations,
        startMinutes: 480,
        deadlineMinutesByNode: {1: 500},
      );
      expect(result, [1, 2]);
    });

    test('reorders deadline stops earliest-first when violated', () {
      // Order [2, 1]: arrive node 2 at 495, node 1 at 515.
      // Node 1 deadline 510 → effective 505. 515 > 505 → violated.
      // Repair: node 1 (deadline 510) before node 2 (no deadline) → [1, 2]
      final result = RouteProvider.repairStopOrder(
        stopIndices: [2, 1],
        durations: durations,
        startMinutes: 480,
        deadlineMinutesByNode: {1: 510},
      );
      expect(result, [1, 2]);
    });

    test('inserts non-deadline stop at cheapest position', () {
      // Asymmetric durations: depot→1=600, depot→2=1200, 1→2=60, 2→1=60
      // depot→3=600, 1→3=600, 2→3=600, 3→1=600, 3→2=600, 3→depot=600
      final asym = [
        [0, 600, 1200, 600],  // from depot
        [600, 0, 60, 600],    // from 1
        [1200, 60, 0, 600],   // from 2
        [600, 600, 600, 0],   // from 3
      ];
      // Node 1 has deadline 510. Node 3 has no deadline.
      // TSP order [3, 1]: arrive 3 at 495, arrive 1 at 515. Node 1 violated.
      // Repair: deadline stops = [1], free stops = [3].
      // Start with [1]. Insert 3: try pos 0 vs pos 1.
      // pos 0: depot→3→1→depot. pos 1: depot→1→3→depot.
      // Cheapest insertion (including 600s dwell) picks lowest extra time.
      final result = RouteProvider.repairStopOrder(
        stopIndices: [3, 1],
        durations: asym,
        startMinutes: 480,
        deadlineMinutesByNode: {1: 510},
      );
      // Node 1 must come first (deadline). Node 3 inserted after.
      expect(result[0], 1);
      expect(result.length, 2);
    });

    test('handles multiple deadline stops sorted by time', () {
      // Nodes 1 and 2 both have deadlines. Node 3 has none.
      // Order [3, 2, 1]: node 1 arrives last, violates deadline.
      // Repair: deadlines sorted → [1 (dl=510), 2 (dl=530)], then insert 3.
      final result = RouteProvider.repairStopOrder(
        stopIndices: [3, 2, 1],
        durations: durations,
        startMinutes: 480,
        deadlineMinutesByNode: {1: 510, 2: 530},
      );
      // Deadline stops in deadline order
      final idx1 = result.indexOf(1);
      final idx2 = result.indexOf(2);
      expect(idx1 < idx2, true, reason: 'Node 1 (earlier deadline) before node 2');
    });

    test('all stops have deadlines — pure deadline sort', () {
      final result = RouteProvider.repairStopOrder(
        stopIndices: [3, 1, 2],
        durations: durations,
        startMinutes: 480,
        deadlineMinutesByNode: {1: 510, 2: 520, 3: 530},
      );
      expect(result, [1, 2, 3]);
    });
  });
}
