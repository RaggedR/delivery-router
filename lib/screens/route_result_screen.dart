import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/route_provider.dart';
import '../services/navigation_launcher.dart';

class RouteResultScreen extends StatelessWidget {
  const RouteResultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<RouteProvider>(
      builder: (context, provider, _) {
        final route = provider.optimizedRoute;
        if (route == null) {
          return const Scaffold(
            body: Center(child: Text('No route data')),
          );
        }

        final arrivalTimes = provider.getArrivalTimes();
        final lateStopIds = provider.getLateStopIds();
        final returnTime = provider.getReturnTime();
        final theme = Theme.of(context);

        return Scaffold(
          appBar: AppBar(title: const Text('Optimized Route')),
          body: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            itemCount: route.orderedStops.length + 2,
            itemBuilder: (context, index) {
              if (index == 0) {
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.primary,
                    child: const Icon(Icons.warehouse, size: 18, color: Colors.white),
                  ),
                  title: Text(
                    provider.depot!.address,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(provider.startTime != null
                      ? 'Depart ${provider.startTime!.format(context)}'
                      : 'Start'),
                );
              }
              if (index == route.orderedStops.length + 1) {
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.primary,
                    child: const Icon(Icons.warehouse, size: 18, color: Colors.white),
                  ),
                  title: Text(
                    provider.depot!.address,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(returnTime != null
                      ? 'Return ${returnTime.format(context)}'
                      : 'Return'),
                );
              }

              final stopIndex = index - 1;
              final stop = route.orderedStops[stopIndex];
              final isLate = lateStopIds.contains(stop.id);
              final arrival = arrivalTimes != null
                  ? arrivalTimes[stopIndex]
                  : null;
              final deadline = provider.deadlineFor(stop.id);

              final parts = <String>[];
              if (arrival != null) {
                parts.add('Arrive ${arrival.format(context)}');
              }
              if (deadline != null) {
                parts.add('Deadline ${deadline.format(context)}');
              }
              final subtitle = parts.join(' · ');

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      isLate ? Colors.red.shade100 : theme.colorScheme.primaryContainer,
                  child: Text(
                    '$index',
                    style: TextStyle(
                      color: isLate ? Colors.red.shade900 : null,
                    ),
                  ),
                ),
                title: Text(
                  stop.address,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: isLate
                      ? TextStyle(color: Colors.red.shade900)
                      : null,
                ),
                subtitle: subtitle.isNotEmpty
                    ? Text(
                        subtitle,
                        style: TextStyle(
                          color: isLate ? Colors.red : null,
                        ),
                      )
                    : null,
                trailing: isLate
                    ? Icon(Icons.warning_amber,
                        color: Colors.red.shade700, size: 20)
                    : null,
              );
            },
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () {
              NavigationLauncher.launchRoute(
                depot: provider.depot!,
                orderedStops: route.orderedStops,
              );
            },
            icon: const Icon(Icons.navigation),
            label: const Text('Navigate'),
          ),
        );
      },
    );
  }
}
