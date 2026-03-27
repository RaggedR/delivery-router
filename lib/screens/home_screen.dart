import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/delivery_location.dart';
import '../providers/route_provider.dart';
import '../services/navigation_launcher.dart';
import '../widgets/address_card.dart';
import 'place_search_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    context.read<RouteProvider>().loadSavedData();
  }

  Future<void> _searchPlace({required bool isDepot}) async {
    final location = await Navigator.of(context).push<DeliveryLocation>(
      MaterialPageRoute(builder: (_) => const PlaceSearchScreen()),
    );
    if (location == null || !mounted) return;

    final provider = context.read<RouteProvider>();
    if (isDepot) {
      await provider.setDepot(location);
    } else {
      provider.addStop(location);
    }
  }

  Future<void> _optimize() async {
    final provider = context.read<RouteProvider>();
    await provider.optimizeRoute();
    if (!mounted) return;

    if (provider.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(provider.error!)),
      );
    } else if (provider.optimizedRoute != null) {
      NavigationLauncher.launchRoute(
        depot: provider.depot!,
        orderedStops: provider.optimizedRoute!.orderedStops,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Delivery Router'),
        actions: [
          Consumer<RouteProvider>(
            builder: (_, provider, _) {
              if (provider.stops.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.delete_sweep),
                tooltip: 'Clear all stops',
                onPressed: () => provider.clearStops(),
              );
            },
          ),
        ],
      ),
      body: Consumer<RouteProvider>(
        builder: (context, provider, child) {
          return Column(
            children: [
              // Depot section
              _DepotTile(
                depot: provider.depot,
                onTap: () => _searchPlace(isDepot: true),
              ),
              const Divider(),
              // Stops header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      'Delivery Stops (${provider.stops.length}/20)',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const Spacer(),
                    if (provider.stops.length < 20)
                      TextButton.icon(
                        onPressed: () => _searchPlace(isDepot: false),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add'),
                      ),
                  ],
                ),
              ),
              // Stops list
              Expanded(
                child: provider.stops.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.local_shipping_outlined,
                              size: 64,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.3),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Add delivery addresses to optimize your route',
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.5),
                                  ),
                            ),
                          ],
                        ),
                      )
                    : ReorderableListView.builder(
                        itemCount: provider.stops.length,
                        onReorder: provider.reorderStops,
                        itemBuilder: (context, index) {
                          final stop = provider.stops[index];
                          return AddressCard(
                            key: ValueKey(stop.id),
                            location: stop,
                            index: index,
                            onDelete: () => provider.removeStop(stop.id),
                          );
                        },
                      ),
              ),
              // Optimize button
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton.icon(
                    onPressed: provider.canOptimize ? _optimize : null,
                    icon: provider.isOptimizing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.route),
                    label: Text(
                      provider.isOptimizing
                          ? 'Optimizing...'
                          : 'Optimize Route',
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DepotTile extends StatelessWidget {
  final DeliveryLocation? depot;
  final VoidCallback onTap;

  const _DepotTile({required this.depot, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: depot != null
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(
          Icons.warehouse,
          color: depot != null
              ? Theme.of(context).colorScheme.onPrimary
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      title: Text(depot?.address ?? 'Set warehouse location'),
      subtitle: depot != null ? null : const Text('Tap to search'),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}
