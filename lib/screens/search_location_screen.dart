import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:vite_captain/services/places_service.dart';

class LocationResult {
  final double lat;
  final double lng;
  final String address;

  const LocationResult({
    required this.lat,
    required this.lng,
    required this.address,
  });
}

class SearchLocationScreen extends StatefulWidget {
  final PlacesService placesService;

  const SearchLocationScreen({
    super.key,
    required this.placesService,
  });

  @override
  State<SearchLocationScreen> createState() => _SearchLocationScreenState();
}

class _SearchLocationScreenState extends State<SearchLocationScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<PlaceSuggestion> _suggestions = <PlaceSuggestion>[];

  bool _loading = false;
  bool _hadSearchError = false;

  Timer? _debounce;
  late final String _sessionToken;

  @override
  void initState() {
    super.initState();
    _sessionToken = _randomToken();
    _controller.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.removeListener(_onQueryChanged);
    _controller.dispose();
    super.dispose();
  }

  String _randomToken() {
    final r = Random();
    return List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  void _onQueryChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 550), () {
      _search(_controller.text);
    });
  }

  Future<void> _search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _suggestions.clear();
        _hadSearchError = false;
        _loading = false;
      });
      return;
    }

    setState(() {
      _loading = true;
      _hadSearchError = false;
    });

    try {
      final results = await widget.placesService.autocomplete(
        trimmed,
        sessionToken: _sessionToken,
        language: 'en',
        components: 'country:in',
      );

      if (!mounted) return;
      setState(() {
        _suggestions
          ..clear()
          ..addAll(results);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hadSearchError = true;
        _suggestions.clear();
      });
    }
  }

  Future<void> _select(PlaceSuggestion suggestion) async {
    setState(() {
      _loading = true;
      _hadSearchError = false;
    });

    try {
      final details = await widget.placesService.getPlaceDetails(
        suggestion.placeId,
        sessionToken: _sessionToken,
        language: 'en',
      );

      if (!mounted) return;
      Navigator.pop(
        context,
        LocationResult(
          lat: details.lat,
          lng: details.lng,
          address: details.address,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hadSearchError = true;
        _suggestions.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Search location'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: 'Enter destination',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () => _controller.clear(),
                        icon: const Icon(Icons.close),
                      ),
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _suggestions.isEmpty
                ? Center(
                    child: Text(
                      _controller.text.trim().isEmpty
                          ? 'Start typing to search locations'
                          : 'No results found',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: _suggestions.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      thickness: 1,
                      color: Colors.grey.shade200,
                    ),
                    itemBuilder: (context, index) {
                      final s = _suggestions[index];
                      return ListTile(
                        leading: const Icon(Icons.place_outlined),
                        title: Text(
                          s.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _select(s),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

