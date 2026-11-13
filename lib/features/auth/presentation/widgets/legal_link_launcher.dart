import 'package:url_launcher/url_launcher.dart';

/// Abre [uri] en el navegador del teléfono. Devuelve `true` si se pudo abrir.
typedef ExternalLinkLauncher = Future<bool> Function(Uri uri);

/// Implementación real: navegador externo. Nunca lanza; devuelve `false` si falla.
Future<bool> launchExternalLink(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
