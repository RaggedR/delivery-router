/// Held-Karp dynamic programming solver for the Travelling Salesman Problem.
///
/// Finds the exact shortest Hamiltonian circuit starting and ending at node 0
/// (the depot). Handles asymmetric distance matrices (A->B may != B->A).
///
/// Time: O(n^2 * 2^n), Space: O(n * 2^n).
/// For n=13: ~1.4M operations — runs in well under a second.
class TspSolver {
  /// Solves TSP on [distanceMatrix] and returns the optimal tour as an ordered
  /// list of node indices, starting and ending with 0 (depot).
  ///
  /// [distanceMatrix] is an n x n matrix where entry [i][j] is the cost
  /// (duration or distance) of travelling from node i to node j.
  ///
  /// Returns a record of (tour, totalCost).
  static ({List<int> tour, int totalCost}) solve(List<List<int>> distanceMatrix) {
    final n = distanceMatrix.length;
    if (n == 0) return (tour: [0], totalCost: 0);
    if (n == 1) return (tour: [0, 0], totalCost: 0);
    if (n == 2) {
      final cost = distanceMatrix[0][1] + distanceMatrix[1][0];
      return (tour: [0, 1, 0], totalCost: cost);
    }

    final fullMask = (1 << n) - 1;
    const infinity = 0x1fffffffffffff; // 2^53 - 1, max safe JS integer

    // dp[mask][i] = minimum cost to visit exactly the nodes in `mask`,
    // ending at node i, starting from node 0.
    // mask always includes node 0 (bit 0) and node i.
    final dp = List.generate(
      1 << n,
      (_) => List.filled(n, infinity),
    );

    // parent[mask][i] = previous node on the optimal path to state (mask, i).
    final parent = List.generate(
      1 << n,
      (_) => List.filled(n, -1),
    );

    // Base case: start at node 0, only node 0 visited.
    dp[1][0] = 0;

    for (var mask = 1; mask < (1 << n); mask++) {
      // Node 0 must always be in the set.
      if (mask & 1 == 0) continue;

      for (var u = 0; u < n; u++) {
        // u must be in the set.
        if (mask & (1 << u) == 0) continue;
        if (dp[mask][u] == infinity) continue;

        for (var v = 0; v < n; v++) {
          // v must not already be in the set.
          if (mask & (1 << v) != 0) continue;

          final nextMask = mask | (1 << v);
          final newCost = dp[mask][u] + distanceMatrix[u][v];

          if (newCost < dp[nextMask][v]) {
            dp[nextMask][v] = newCost;
            parent[nextMask][v] = u;
          }
        }
      }
    }

    // Find the best last node before returning to depot (node 0).
    var bestCost = infinity;
    var lastNode = -1;
    for (var u = 1; u < n; u++) {
      final cost = dp[fullMask][u] + distanceMatrix[u][0];
      if (cost < bestCost) {
        bestCost = cost;
        lastNode = u;
      }
    }

    // Reconstruct tour by backtracking through parent pointers.
    final tour = <int>[];
    var currentMask = fullMask;
    var currentNode = lastNode;
    while (currentNode != 0) {
      tour.add(currentNode);
      final prev = parent[currentMask][currentNode];
      currentMask ^= (1 << currentNode);
      currentNode = prev;
    }
    tour.add(0); // start
    final reversedTour = tour.reversed.toList();
    reversedTour.add(0); // return to depot

    return (tour: reversedTour, totalCost: bestCost);
  }
}
