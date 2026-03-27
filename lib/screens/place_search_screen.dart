import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/delivery_location.dart';
import '../services/maps_api_service.dart';

/// Full-screen search with Places Autocomplete.
/// Returns the selected [DeliveryLocation] via Navigator.pop.
/// Shows recently-used addresses when the search field is empty.
class PlaceSearchScreen extends StatefulWidget {
  const PlaceSearchScreen({super.key});

  @override
  State<PlaceSearchScreen> createState() => _PlaceSearchScreenState();
}

class _PlaceSearchScreenState extends State<PlaceSearchScreen> {
  static const _historyKey = 'address_history';
  static const _maxHistory = 20;

  final _mapsApi = MapsApiService();
  final _controller = TextEditingController();
  Timer? _debounce;
  List<PlacePrediction> _predictions = [];
  List<DeliveryLocation> _history = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_historyKey);
    if (json != null) {
      final list = jsonDecode(json) as List;
      setState(() {
        _history = list
            .map((s) => DeliveryLocation.fromJson(s as Map<String, dynamic>))
            .toList();
      });
    }
  }

  static Future<void> addToHistory(DeliveryLocation location) async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_historyKey);
    final List<DeliveryLocation> history;
    if (json != null) {
      final list = jsonDecode(json) as List;
      history = list
          .map((s) => DeliveryLocation.fromJson(s as Map<String, dynamic>))
          .toList();
    } else {
      history = [];
    }
    // Remove duplicate if already in history, then prepend.
    history.removeWhere((h) => h.address == location.address);
    history.insert(0, location);
    // Keep only the most recent entries.
    if (history.length > _maxHistory) {
      history.removeRange(_maxHistory, history.length);
    }
    await prefs.setString(
      _historyKey,
      jsonEncode(history.map((h) => h.toJson()).toList()),
    );
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _search(query);
    });
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _predictions = []);
      return;
    }
    setState(() => _isLoading = true);
    final results = await _mapsApi.autocomplete(query);
    if (mounted) {
      setState(() {
        _predictions = results;
        _isLoading = false;
      });
    }
  }

  Future<void> _selectPrediction(PlacePrediction prediction) async {
    setState(() => _isLoading = true);
    final location = await _mapsApi.getPlaceDetails(prediction.placeId);
    if (mounted && location != null) {
      await addToHistory(location);
      Navigator.of(context).pop(location);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not get location details')),
      );
      setState(() => _isLoading = false);
    }
  }

  void _selectFromHistory(DeliveryLocation location) {
    addToHistory(location);
    Navigator.of(context).pop(location);
  }

  @override
  Widget build(BuildContext context) {
    final showHistory =
        _controller.text.trim().isEmpty && _history.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search address...',
            border: InputBorder.none,
          ),
          onChanged: _onSearchChanged,
        ),
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      body: showHistory
          ? ListView.builder(
              itemCount: _history.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      'Recent addresses',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.5),
                          ),
                    ),
                  );
                }
                final loc = _history[index - 1];
                return ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(loc.address),
                  onTap: () => _selectFromHistory(loc),
                );
              },
            )
          : ListView.builder(
              itemCount: _predictions.length,
              itemBuilder: (context, index) {
                final p = _predictions[index];
                return ListTile(
                  leading: const Icon(Icons.location_on_outlined),
                  title: Text(p.description),
                  onTap: () => _selectPrediction(p),
                );
              },
            ),
    );
  }
}
