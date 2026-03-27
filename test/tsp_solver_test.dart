import 'package:flutter_test/flutter_test.dart';
import 'package:delivery_router/services/tsp_solver.dart';

void main() {
  group('TspSolver', () {
    test('single node returns trivial tour', () {
      final result = TspSolver.solve([[0]]);
      expect(result.tour, [0, 0]);
      expect(result.totalCost, 0);
    });

    test('two nodes returns correct round trip', () {
      final result = TspSolver.solve([
        [0, 10],
        [15, 0],
      ]);
      expect(result.tour, [0, 1, 0]);
      expect(result.totalCost, 25); // 10 + 15
    });

    test('symmetric 4-city example finds optimal tour', () {
      // Classic example:
      //   0 --10-- 1
      //   |        |
      //  25       35
      //   |        |
      //   3 --30-- 2
      // Plus diagonals: 0-2=20, 1-3=15
      // Optimal tour: 0 -> 1 -> 3 -> 2 -> 0 = 10+15+30+20 = 75
      // or equivalently 0 -> 2 -> 3 -> 1 -> 0 = 20+30+15+10 = 75
      final matrix = [
        [0, 10, 20, 25],
        [10, 0, 35, 15],
        [20, 35, 0, 30],
        [25, 15, 30, 0],
      ];
      final result = TspSolver.solve(matrix);
      expect(result.totalCost, 75);
      // Tour starts and ends with 0
      expect(result.tour.first, 0);
      expect(result.tour.last, 0);
      // All cities visited exactly once (except depot which appears twice)
      expect(result.tour.length, 5); // 4 cities + return
      final visited = result.tour.sublist(0, result.tour.length - 1).toSet();
      expect(visited, {0, 1, 2, 3});
    });

    test('asymmetric matrix respects direction', () {
      // A->B costs differently than B->A
      final matrix = [
        [0, 5, 100],
        [100, 0, 5],
        [5, 100, 0],
      ];
      // Optimal: 0->1->2->0 = 5+5+5 = 15
      // Reverse: 0->2->1->0 = 100+100+100 = 300
      final result = TspSolver.solve(matrix);
      expect(result.totalCost, 15);
      expect(result.tour, [0, 1, 2, 0]);
    });

    test('handles 6 cities correctly', () {
      // All edges cost 1 except the "wrong" direction which costs 100
      // This creates a clear optimal Hamiltonian circuit
      final n = 6;
      final matrix = List.generate(n, (i) => List.generate(n, (j) {
        if (i == j) return 0;
        // Cheap path: 0->1->2->3->4->5->0
        if (j == (i + 1) % n) return 1;
        return 100;
      }));
      final result = TspSolver.solve(matrix);
      expect(result.totalCost, 6); // 6 edges of cost 1
    });

    test('empty matrix returns trivial result', () {
      final result = TspSolver.solve([]);
      expect(result.tour, [0]);
      expect(result.totalCost, 0);
    });
  });
}
