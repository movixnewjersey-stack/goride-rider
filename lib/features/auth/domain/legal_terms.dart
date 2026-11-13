/// Documentos legales que el pasajero acepta al crear su cuenta.
/// ÚNICO lugar de la app donde viven las versiones y los enlaces.
enum LegalDocument {
  terms(
    title: 'Términos y condiciones',
    url: 'https://goride.website/terminos-y-condiciones/',
  ),
  privacy(
    title: 'Política de privacidad',
    url: 'https://goride.website/privacy-policy/',
  );

  const LegalDocument({required this.title, required this.url});

  final String title;
  final String url;

  Uri get uri => Uri.parse(url);
}

abstract class LegalTerms {
  LegalTerms._();

  /// Deben ser IGUALES a las del servidor (`TermsAcceptanceGate`); si no,
  /// el registro se rechaza con `TERMS_VERSION_OUTDATED`.
  static const String termsVersion = '1.0';
  static const String privacyVersion = '1.0';
}
