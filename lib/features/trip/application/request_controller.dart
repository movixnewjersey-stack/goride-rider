import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/util/idempotency.dart';
import '../data/trip_repository.dart';
import '../domain/trip.dart';

enum QuoteStatus { idle, loading, ready, error }

enum BookingStatus { idle, submitting, error, done }

class RequestState {
  const RequestState({
    this.pickup,
    this.dropoff,
    this.passengers = 1,
    this.quoteStatus = QuoteStatus.idle,
    this.quote,
    this.quoteError,
    this.bookingStatus = BookingStatus.idle,
    this.bookingError,
    this.bookingOutcomeUnknown = false,
    this.priceChangedTo,
    this.createdTrip,
    this.blockingTrip,
  });

  final GeoPoint? pickup;
  final GeoPoint? dropoff;
  final int passengers;
  final QuoteStatus quoteStatus;
  final Quote? quote;
  final String? quoteError;
  final BookingStatus bookingStatus;
  final String? bookingError;

  /// No sabemos si el servidor creó la solicitud: se ofrece «Reintentar»
  /// (con la MISMA clave, así que nunca se duplica).
  final bool bookingOutcomeUnknown;

  /// El precio cambió entre cotizar y pedir: hay que reconfirmar.
  final double? priceChangedTo;
  final Trip? createdTrip;

  /// El servidor dice que ya hay un viaje en marcha.
  final Trip? blockingTrip;

  bool get canRequest =>
      quoteStatus == QuoteStatus.ready && quote != null && bookingStatus != BookingStatus.submitting;

  RequestState copyWith({
    GeoPoint? pickup,
    bool clearPickup = false,
    GeoPoint? dropoff,
    bool clearDropoff = false,
    int? passengers,
    QuoteStatus? quoteStatus,
    Quote? quote,
    bool clearQuote = false,
    String? quoteError,
    bool clearQuoteError = false,
    BookingStatus? bookingStatus,
    String? bookingError,
    bool clearBookingError = false,
    bool? bookingOutcomeUnknown,
    double? priceChangedTo,
    bool clearPriceChanged = false,
    Trip? createdTrip,
    Trip? blockingTrip,
    bool clearBlocking = false,
  }) {
    return RequestState(
      pickup: clearPickup ? null : (pickup ?? this.pickup),
      dropoff: clearDropoff ? null : (dropoff ?? this.dropoff),
      passengers: passengers ?? this.passengers,
      quoteStatus: quoteStatus ?? this.quoteStatus,
      quote: clearQuote ? null : (quote ?? this.quote),
      quoteError: clearQuoteError ? null : (quoteError ?? this.quoteError),
      bookingStatus: bookingStatus ?? this.bookingStatus,
      bookingError: clearBookingError ? null : (bookingError ?? this.bookingError),
      bookingOutcomeUnknown: bookingOutcomeUnknown ?? this.bookingOutcomeUnknown,
      priceChangedTo: clearPriceChanged ? null : (priceChangedTo ?? this.priceChangedTo),
      createdTrip: createdTrip ?? this.createdTrip,
      blockingTrip: clearBlocking ? null : (blockingTrip ?? this.blockingTrip),
    );
  }
}

/// Cotizar y pedir. Garantías:
///  - jamás se muestra éxito si el servidor no devolvió un viaje;
///  - doble toque: la segunda llamada se ignora mientras hay una en vuelo;
///  - reintentos de la MISMA solicitud usan la MISMA `idempotency_key`.
class RequestController extends StateNotifier<RequestState> {
  /// Lectura pública del estado actual (para pruebas).
  RequestState get snapshot => state;

  RequestController(this._repo, {String Function()? keyFactory})
      : _newKey = keyFactory ?? newIdempotencyKey,
        super(const RequestState());

  final TripRepository _repo;
  final String Function() _newKey;

  String? _key;
  String? _keyQuoteId;
  int _quoteSeq = 0;

  void setPickup(GeoPoint p) {
    state = state.copyWith(pickup: p);
    _requote();
  }

  void setDropoff(GeoPoint p) {
    state = state.copyWith(dropoff: p);
    _requote();
  }

  void swap() {
    final p = state.pickup;
    final d = state.dropoff;
    state = RequestState(pickup: d, dropoff: p, passengers: state.passengers);
    _requote();
  }

  void setPassengers(int n) {
    if (n < 1 || n == state.passengers) {
      return;
    }
    state = state.copyWith(passengers: n);
    _requote();
  }

  void _requote() {
    // Cualquier cambio invalida la cotización y la clave del intento anterior.
    _key = null;
    _keyQuoteId = null;
    state = state.copyWith(
      clearQuote: true,
      clearQuoteError: true,
      clearBookingError: true,
      clearPriceChanged: true,
      clearBlocking: true,
      bookingStatus: BookingStatus.idle,
      bookingOutcomeUnknown: false,
      quoteStatus: QuoteStatus.idle,
    );
    if (state.pickup != null && state.dropoff != null) {
      requestQuote();
    }
  }

  Future<void> requestQuote() async {
    final pickup = state.pickup;
    final dropoff = state.dropoff;
    if (pickup == null || dropoff == null) {
      return;
    }
    final seq = ++_quoteSeq;
    state = state.copyWith(quoteStatus: QuoteStatus.loading, clearQuoteError: true);
    try {
      final quote = await _repo.quote(pickup: pickup, dropoff: dropoff, passengers: state.passengers);
      if (!mounted || seq != _quoteSeq) {
        return; // llegó una respuesta vieja: se ignora
      }
      state = state.copyWith(quoteStatus: QuoteStatus.ready, quote: quote);
    } catch (e) {
      if (!mounted || seq != _quoteSeq) {
        return;
      }
      state = state.copyWith(quoteStatus: QuoteStatus.error, quoteError: userMessage(e), clearQuote: true);
    }
  }

  /// «Pedir viaje». Seguro contra doble toque.
  Future<void> confirm() async {
    final quote = state.quote;
    if (quote == null || state.bookingStatus == BookingStatus.submitting || state.bookingStatus == BookingStatus.done) {
      return;
    }
    if (quote.isExpired()) {
      await requestQuote();
      state = state.copyWith(bookingError: 'La cotización venció. Revisa el precio y vuelve a confirmar.');
      return;
    }

    // Se marca "enviando" ANTES de cualquier await: bloquea el segundo toque.
    state = state.copyWith(
      bookingStatus: BookingStatus.submitting,
      clearBookingError: true,
      clearPriceChanged: true,
      bookingOutcomeUnknown: false,
    );

    if (_key == null || _keyQuoteId != quote.quoteId) {
      _key = _newKey();
      _keyQuoteId = quote.quoteId;
    }

    try {
      final result = await _repo.book(quoteId: quote.quoteId, idempotencyKey: _key!);
      if (!mounted) {
        return;
      }
      _key = null;
      _keyQuoteId = null;
      state = state.copyWith(bookingStatus: BookingStatus.done, createdTrip: result.trip);
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      await _onBookingError(e);
    } catch (e) {
      if (mounted) {
        state = state.copyWith(bookingStatus: BookingStatus.error, bookingError: userMessage(e));
      }
    }
  }

  Future<void> _onBookingError(ApiException e) async {
    switch (e.code) {
      case 'PRICE_CHANGED':
        final price = e.data?['price'];
        final total = price is Map ? double.tryParse('${price['total']}') : null;
        _key = null;
        _keyQuoteId = null;
        state = state.copyWith(
          bookingStatus: BookingStatus.error,
          bookingError: 'El precio cambió. Revisa el nuevo valor y confirma de nuevo.',
          priceChangedTo: total,
        );
        await requestQuote();
        return;
      case 'QUOTE_EXPIRED':
      case 'QUOTE_INVALID':
        _key = null;
        _keyQuoteId = null;
        state = state.copyWith(
          bookingStatus: BookingStatus.error,
          bookingError: 'La cotización venció. Revisa el precio y vuelve a confirmar.',
        );
        await requestQuote();
        return;
      case 'ACTIVE_TRIP_EXISTS':
        _key = null;
        _keyQuoteId = null;
        final t = e.data?['trip'];
        state = state.copyWith(
          bookingStatus: BookingStatus.error,
          bookingError: e.message.isNotEmpty ? e.message : 'Ya tienes un viaje en curso.',
          blockingTrip: t is Map ? Trip.fromJson(Map<String, dynamic>.from(t)) : null,
        );
        return;
      default:
        // Red caída o respuesta perdida: la clave se CONSERVA para el reintento.
        final unknown = e.outcomeUnknown || e.isNetwork;
        state = state.copyWith(
          bookingStatus: BookingStatus.error,
          bookingError: unknown
              ? 'No pudimos confirmar si tu solicitud llegó. Toca «Reintentar»: no se duplicará.'
              : userMessage(e),
          bookingOutcomeUnknown: unknown,
        );
    }
  }

  /// Limpia todo tras abrir el viaje.
  void reset() {
    _key = null;
    _keyQuoteId = null;
    _quoteSeq++;
    state = const RequestState();
  }
}
