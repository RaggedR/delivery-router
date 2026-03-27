import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/delivery_location.dart';
import '../models/saved_address.dart';
import '../services/address_book.dart';
import '../services/maps_api_service.dart';

/// Full-screen search with Places Autocomplete.
/// Returns the selected [DeliveryLocation] via Navigator.pop.
/// Shows saved addresses and recent addresses when the search field is empty.
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
  List<SavedAddress> _saved = [];
  List<DeliveryLocation> _history = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final saved = await AddressBook.load();
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_historyKey);
    List<DeliveryLocation> history = [];
    if (json != null) {
      final list = jsonDecode(json) as List;
      history = list
          .map((s) => DeliveryLocation.fromJson(s as Map<String, dynamic>))
          .toList();
    }
    if (mounted) {
      setState(() {
        _saved = saved;
        _history = history;
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
    history.removeWhere((h) => h.address == location.address);
    history.insert(0, location);
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
    if (query.trim().isEmpty) {
      setState(() => _predictions = []);
      return;
    }
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
      if (mounted) {
        _offerToSave(location);
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not get location details')),
      );
      setState(() => _isLoading = false);
    }
  }

  void _selectSaved(DeliveryLocation location) {
    addToHistory(location);
    Navigator.of(context).pop(location);
  }

  void _selectFromHistory(DeliveryLocation location) {
    addToHistory(location);
    _offerToSave(location);
  }

  /// After selecting an address, briefly offer to save it, then return it.
  void _offerToSave(DeliveryLocation location) {
    // Check if already saved
    final alreadySaved = _saved.any((s) => s.location.address == location.address);
    if (alreadySaved) {
      Navigator.of(context).pop(location);
      return;
    }

    showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => _SaveAddressSheet(address: location.address),
    ).then((shouldSave) async {
      if (shouldSave == true) {
        // The sheet already saved it
        await _loadData();
      }
      if (mounted) {
        Navigator.of(context).pop(location);
      }
    });
  }

  Future<void> _deleteSaved(SavedAddress saved) async {
    await AddressBook.delete(saved.location.address);
    await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final isSearching = _controller.text.trim().isNotEmpty;

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
      body: isSearching
          ? _buildSearchResults()
          : _buildSavedAndRecent(),
    );
  }

  Widget _buildSearchResults() {
    return ListView.builder(
      itemCount: _predictions.length,
      itemBuilder: (context, index) {
        final p = _predictions[index];
        return ListTile(
          leading: const Icon(Icons.location_on_outlined),
          title: Text(p.description),
          onTap: () => _selectPrediction(p),
        );
      },
    );
  }

  Widget _buildSavedAndRecent() {
    final items = <Widget>[];

    if (_saved.isNotEmpty) {
      items.add(_sectionHeader('Saved addresses'));
      for (final s in _saved) {
        items.add(ListTile(
          leading: const Icon(Icons.bookmark),
          title: Text(s.name),
          subtitle: Text(
            s.location.address,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => _deleteSaved(s),
          ),
          onTap: () => _selectSaved(s.location),
        ));
      }
    }

    // Filter history to exclude addresses already in saved
    final savedAddresses = _saved.map((s) => s.location.address).toSet();
    final filteredHistory =
        _history.where((h) => !savedAddresses.contains(h.address)).toList();

    if (filteredHistory.isNotEmpty) {
      items.add(_sectionHeader('Recent'));
      for (final loc in filteredHistory) {
        items.add(ListTile(
          leading: const Icon(Icons.history),
          title: Text(loc.address),
          onTap: () => _selectFromHistory(loc),
        ));
      }
    }

    if (items.isEmpty) {
      return const Center(
        child: Text('Start typing to search for an address'),
      );
    }

    return ListView(children: items);
  }

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.5),
            ),
      ),
    );
  }
}

/// Bottom sheet for saving an address with a name.
class _SaveAddressSheet extends StatefulWidget {
  final String address;
  const _SaveAddressSheet({required this.address});

  @override
  State<_SaveAddressSheet> createState() => _SaveAddressSheetState();
}

class _SaveAddressSheetState extends State<_SaveAddressSheet> {
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Save to address book?',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            widget.address,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'e.g. Mum\'s house, Office, Warehouse',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Skip'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _save,
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    // We need the full location to save. Parse it from the address.
    // The parent already has the location — we signal back with true.
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getString('address_history');
    if (historyJson != null) {
      final list = jsonDecode(historyJson) as List;
      final locations = list
          .map((s) => DeliveryLocation.fromJson(s as Map<String, dynamic>))
          .toList();
      final match = locations.where((l) => l.address == widget.address).firstOrNull;
      if (match != null) {
        await AddressBook.save(name, match);
      }
    }
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }
}
