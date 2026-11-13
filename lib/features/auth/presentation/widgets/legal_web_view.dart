import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Avisos que la página legal le da a la pantalla que la contiene.
class LegalPageCallbacks {
  const LegalPageCallbacks({
    required this.onProgress,
    required this.onLoaded,
    required this.onError,
    required this.onExternalLink,
  });

  /// Avance de la carga, de 0 a 100.
  final ValueChanged<int> onProgress;

  /// La página terminó de cargar y ya está lista para leerse.
  final VoidCallback onLoaded;

  /// La página principal no se pudo cargar (red caída, 404, 5xx...).
  final ValueChanged<String> onError;

  /// El usuario tocó un enlace que sale de goride.website (correo, otro sitio...).
  final ValueChanged<Uri> onExternalLink;
}

/// Crea la vista de la página legal. Se puede reemplazar en pruebas.
typedef LegalPageBuilder = Widget Function(
  BuildContext context,
  Uri uri,
  LegalPageCallbacks callbacks,
);

/// Constructor real: una WebView que muestra la página pública.
Widget webViewLegalPageBuilder(
  BuildContext context,
  Uri uri,
  LegalPageCallbacks callbacks,
) {
  return LegalWebViewPage(uri: uri, callbacks: callbacks);
}

/// Oculta lo que NO es el documento (cabecera, menú, pie, avisos flotantes como
/// el de "Instalar GoRide") para que se lea solo el texto legal. Si el sitio
/// cambia de tema y esto deja de coincidir, el documento sigue siendo legible.
const String kLegalHideChromeScript = r'''
(function () {
  try {
    var css = 'body > header, body > footer, #masthead, #colophon, .site-header, .site-footer, ' +
      '#wpadminbar, nav, [role="banner"], [role="contentinfo"], [role="dialog"], dialog ' +
      '{ display: none !important; } ' +
      'html, body { margin-top: 0 !important; padding-top: 0 !important; }';
    var style = document.createElement('style');
    style.textContent = css;
    document.head.appendChild(style);
    var all = document.querySelectorAll('body *');
    for (var i = 0; i < all.length; i++) {
      var pos = window.getComputedStyle(all[i]).position;
      if ((pos === 'fixed' || pos === 'sticky') && !all[i].querySelector('main, article')) {
        all[i].style.setProperty('display', 'none', 'important');
      }
    }
  } catch (e) {}
})();
''';

class LegalWebViewPage extends StatefulWidget {
  const LegalWebViewPage({
    super.key,
    required this.uri,
    required this.callbacks,
  });

  final Uri uri;
  final LegalPageCallbacks callbacks;

  @override
  State<LegalWebViewPage> createState() => _LegalWebViewPageState();
}

class _LegalWebViewPageState extends State<LegalWebViewPage> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: widget.callbacks.onProgress,
          onNavigationRequest: _onNavigationRequest,
          onPageFinished: (_) => _onPageFinished(),
          onWebResourceError: (error) {
            // Solo importa si falló la página principal (no una imagen o un script).
            if (error.isForMainFrame ?? true) {
              widget.callbacks.onError(error.description);
            }
          },
          onHttpError: (error) {
            final status = error.response?.statusCode ?? 0;
            final failedUri = error.request?.uri;
            final isMainPage =
                failedUri != null && failedUri.host == widget.uri.host && failedUri.path == widget.uri.path;

            if (isMainPage && status >= 400) {
              widget.callbacks.onError('HTTP $status');
            }
          },
        ),
      )
      ..loadRequest(widget.uri);
  }

  NavigationDecision _onNavigationRequest(NavigationRequest request) {
    final target = Uri.tryParse(request.url);

    if (target == null) {
      return NavigationDecision.prevent;
    }

    final isWeb = target.scheme == 'https' || target.scheme == 'http';

    if (isWeb && target.host == widget.uri.host) {
      return NavigationDecision.navigate;
    }

    // Correos, teléfonos u otros sitios: fuera de la ventana legal.
    widget.callbacks.onExternalLink(target);
    return NavigationDecision.prevent;
  }

  Future<void> _onPageFinished() async {
    try {
      await _controller.runJavaScript(kLegalHideChromeScript);
    } catch (_) {
      // El documento sigue siendo legible aunque no se pudo limpiar la página.
    }

    widget.callbacks.onLoaded();
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}
