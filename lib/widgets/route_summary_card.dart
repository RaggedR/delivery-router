import 'package:flutter/material.dart';
import '../models/optimized_route.dart';

class RouteSummaryCard extends StatelessWidget {
  final OptimizedRoute route;

  const RouteSummaryCard({super.key, required this.route});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _Stat(
              icon: Icons.timer_outlined,
              value: route.formattedDuration,
              label: 'Drive time',
              color: theme.colorScheme.primary,
            ),
            _Stat(
              icon: Icons.straighten,
              value: route.formattedDistance,
              label: 'Distance',
              color: theme.colorScheme.secondary,
            ),
            _Stat(
              icon: Icons.location_on,
              value: '${route.orderedStops.length}',
              label: 'Stops',
              color: theme.colorScheme.tertiary,
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _Stat({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
