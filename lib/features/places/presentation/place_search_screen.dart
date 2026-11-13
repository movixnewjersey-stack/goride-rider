import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/providers.dart';
import '../../../core/util/idempotency.dart';
import '../../trip/domain/trip.dart';
import '../domain/place.dart';

/// Busca una dirección (vía servidor) y devuelve el punto elegido con `Navigator.pop`.
class PlaceSearchScreen extends ConsumerStatefulWidget {
  const PlaceSearchScreen({super.key, required this.title, this.biasLat, this.biasLng});

  final String title;
  final double? biasLat;
  final double? biasLng;

  @override
  ConsumerState<PlaceSearchScreen> createState() => _PlaceSearchScreenState();
}

class _PlaceSearchScreenState extends ConsumerState<PlaceSearchScreen> {
  final _controller = TextEditingController();
  final String _session = newSearchSession();
  Timer? _debounce;
  int _seq = 0;
  bool _loading = false;
  bool _resolving = false;
  String? _error;
  List<PlaceSuggestion> _results = const [];

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.length < 3) {
      setState(() {
        _results = const [];
        _error = null;
        _loading = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(q));
  }

  Future<void> _search(String q) async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await ref
          .read(placesRepositoryProvider)
          .search(q, lat: widget.biasLat, lng: widget.biasLng, session: _session);
      if (!mounted || seq != _seq) {
        return;
      }
      setState(() => _results = r);
    } catch (e) {
      if (mounted && seq == _seq) {
        setState(() {
          _results = const [];
          _error = userMessage(e);
        });
      }
    } finally {
      if (mounted && seq == _seq) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _pick(PlaceSuggestion s) async {
    if (_resolving) {
      return;
    }
    setState(() {
      _resolving = true;
      _error = null;
    });
    try {
      final GeoPoint point = await ref.read(placesRepositoryProvider).details(s.placeId, session: _session);
      if (mounted) {
        Navigator.of(context).pop(point);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _resolving = false;
          _error = userMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              key: const Key('place_search_field'),
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Escribe la dirección',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : null,
              ),
              onChanged: _onChanged,
            ),
          ),
          if (_resolving) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _results.length,
              itemBuilder: (context, i) {
                final s = _results[i];
                return ListTile(
                  leading: const Icon(Icons.place_outlined),
                  title: Text(s.primary),
                  subtitle: s.secondary.isEmpty ? null : Text(s.secondary),
                  onTap: _resolving ? null : () => _pick(s),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
