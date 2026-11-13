import 'package:equatable/equatable.dart';

class PlaceSuggestion extends Equatable {
  const PlaceSuggestion({required this.placeId, required this.primary, required this.secondary});

  factory PlaceSuggestion.fromJson(Map<String, dynamic> j) => PlaceSuggestion(
        placeId: '${j['place_id']}',
        primary: '${j['primary'] ?? ''}',
        secondary: '${j['secondary'] ?? ''}',
      );

  final String placeId;
  final String primary;
  final String secondary;

  @override
  List<Object?> get props => [placeId, primary, secondary];
}
