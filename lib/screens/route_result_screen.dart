import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/route_provider.dart';
import '../services/maps_api_service.dart';
import '../services/navigation_launcher.dart';
import '../widgets/route_summary_card.dart';

class RouteResultScreen extends StatefulWidget {
  const RouteResultScreen({super.key});

  @override
  State<RouteResultScreen> createState() => _RouteResultScreenState();
}

class _RouteResultScreenState extends State<RouteResultScreen> {
  Set<Polyline> _polylines = {};
  bool _loadingPolyline = true;

  @override
  void initState() {
    super.initState();
    _loadPolyline();
  }

  Future<void> _loadPolyline() async {
    final provider = context.read<RouteProvider>();
    final route = provider.optimizedRoute;
    final depot = provider.depot;
    if (route == null || depot == null) return;

    final mapsApi = MapsApiService();
    final polylineEncoded = await mapsApi.getDirectionsPolyline(
      origin: depot,
      destination: depot,
      waypoints: route.orderedStops,
    );

    if (polylineEncoded != null && mounted) {
      final points = _decodePolyline(polylineEncoded);
      setState(() {
        _polylines = {
          Polyline(
            polylineId: const PolylineId('route'),
            points: points,
            color: Theme.of(context).colorScheme.primary,
            width: 4,
          ),
        };
        _loadingPolyline = false;
      });
    } else if (mounted) {
      setState(() => _loadingPolyline = false);
    }
  }

  /// Decodes a Google Maps encoded polyline string into a list of LatLng points.
  List<LatLng> _decodePolyline(String encoded) {
    final points = <LatLng>[];
    var index = 0;
    var lat = 0;
    var lng = 0;

    while (index < encoded.length) {
      var shift = 0;
      var result = 0;
      int b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }

  Set<Marker> _buildMarkers(RouteProvider provider) {
    final markers = <Marker>{};
    final depot = provider.depot!;
    final route = provider.optimizedRoute!;

    // Depot marker
    markers.add(Marker(
      markerId: const MarkerId('depot'),
      position: LatLng(depot.lat, depot.lng),
      infoWindow: InfoWindow(title: 'Warehouse', snippet: depot.address),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
    ));

    // Numbered stop markers
    for (var i = 0; i < route.orderedStops.length; i++) {
      final stop = route.orderedStops[i];
      markers.add(Marker(
        markerId: MarkerId(stop.id),
        position: LatLng(stop.lat, stop.lng),
        infoWindow: InfoWindow(
          title: 'Stop ${i + 1}',
          snippet: stop.address,
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ));
    }

    return markers;
  }

  LatLngBounds _computeBounds(RouteProvider provider) {
    final depot = provider.depot!;
    final stops = provider.optimizedRoute!.orderedStops;
    final allLats = [depot.lat, ...stops.map((s) => s.lat)];
    final allLngs = [depot.lng, ...stops.map((s) => s.lng)];

    return LatLngBounds(
      southwest: LatLng(
        allLats.reduce(min) - 0.01,
        allLngs.reduce(min) - 0.01,
      ),
      northeast: LatLng(
        allLats.reduce(max) + 0.01,
        allLngs.reduce(max) + 0.01,
      ),
    );
  }

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

        final markers = _buildMarkers(provider);
        final bounds = _computeBounds(provider);

        return Scaffold(
          appBar: AppBar(title: const Text('Optimized Route')),
          body: Column(
            children: [
              RouteSummaryCard(route: route),
              // Map preview — compact
              SizedBox(
                height: 200,
                child: Stack(
                  children: [
                    GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: LatLng(
                          provider.depot!.lat,
                          provider.depot!.lng,
                        ),
                        zoom: 12,
                      ),
                      markers: markers,
                      polylines: _polylines,
                      mapToolbarEnabled: false,
                      zoomControlsEnabled: false,
                      myLocationButtonEnabled: false,
                      style: '[{"featureType":"poi","stylers":[{"visibility":"off"}]},{"featureType":"transit","stylers":[{"visibility":"off"}]}]',
                      onMapCreated: (controller) {
                        controller.animateCamera(
                          CameraUpdate.newLatLngBounds(bounds, 50),
                        );
                      },
                    ),
                    if (_loadingPolyline)
                      const Center(child: CircularProgressIndicator()),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Ordered stop list — takes remaining space
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  itemCount: route.orderedStops.length + 2, // +2 for depot start/end
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      // Depot start
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 14,
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          child: const Icon(Icons.warehouse, size: 14, color: Colors.white),
                        ),
                        title: Text(
                          provider.depot!.address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: const Text('Start'),
                      );
                    }
                    if (index == route.orderedStops.length + 1) {
                      // Depot end
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 14,
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          child: const Icon(Icons.warehouse, size: 14, color: Colors.white),
                        ),
                        title: Text(
                          provider.depot!.address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: const Text('Return'),
                      );
                    }
                    final stop = route.orderedStops[index - 1];
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 14,
                        child: Text(
                          '$index',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      title: Text(
                        stop.address,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  },
                ),
              ),
            ],
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
