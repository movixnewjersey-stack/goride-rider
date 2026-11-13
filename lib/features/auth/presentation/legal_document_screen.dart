import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/legal_terms.dart';
import 'widgets/legal_link_launcher.dart';
import 'widgets/legal_web_view.dart';

/// Abre un documento legal en una pantalla modal DENTRO de la app.
///
/// Cerrar la ventana NO es aceptar nada: la ruta no devuelve ningún valor y no
/// toca el estado de quien la abrió (la casilla del registro queda como estaba).
Future<void> showLegalDocument(
  BuildContext context,
  LegalDocument document, {
  LegalPageBuilder pageBuilder = webViewLegalPageBuilder,
  ExternalLinkLauncher externalLauncher = launchExternalLink,
  Duration loadTimeout = const Duration(seconds: 25),
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => LegalDocumentScreen(
        document: document,
        pageBuilder: pageBuilder,
        externalLauncher: externalLauncher,
        loadTimeout: loadTimeout,
      ),
    ),
  );
}

enum _LoadState { loading, ready, error }

/// Visor integrado de un documento legal publicado en el sitio. El texto vive
/// SOLO en la página pública (no hay una segunda copia en la app).
class LegalDocumentScreen extends StatefulWidget {
  const LegalDocumentScreen({
    super.key,
    required this.document,
    this.pageBuilder = webViewLegalPageBuilder,
    this.externalLauncher = launchExternalLink,
    this.loadTimeout = const Duration(seconds: 25),
  });

  final LegalDocument document;
  final LegalPageBuilder pageBuilder;
  final ExternalLinkLauncher externalLauncher;

  /// Si la página no termina de cargar en este tiempo, se muestra el error.
  final Duration loadTimeout;

  @override
  State<LegalDocumentScreen> createState() => _LegalDocumentScreenState();
}

class _LegalDocumentScreenState extends State<LegalDocumentScreen> {
  _LoadState _state = _LoadState.loading;
  int _progress = 0;
  int _attempt = 0;
  Timer? _timeout;

  @override
  void initState() {
    super.initState();
    _startTimeout();
  }

  @override
  void dispose() {
    _timeout?.cancel();
    super.dispose();
  }

  void _startTimeout() {
    _timeout?.cancel();
    _timeout = Timer(widget.loadTimeout, () {
      if (mounted && _state == _LoadState.loading) {
        setState(() => _state = _LoadState.error);
      }
    });
  }

  void _onProgress(int value) {
    if (mounted && _state == _LoadState.loading) {
      setState(() => _progress = value.clamp(0, 100));
    }
  }

  void _onLoaded() {
    // Un error ya mostrado manda: algunas plataformas avisan "terminó" tras fallar.
    if (mounted && _state == _LoadState.loading) {
      _timeout?.cancel();
      setState(() => _state = _LoadState.ready);
    }
  }

  void _onError(String _) {
    if (mounted && _state != _LoadState.error) {
      _timeout?.cancel();
      setState(() => _state = _LoadState.error);
    }
  }

  Future<void> _openExternal(Uri uri) async {
    final opened = await widget.externalLauncher(uri);

    if (!opened && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('No se pudo abrir el navegador. Inténtalo de nuevo.'),
          ),
        );
    }
  }

  void _retry() {
    setState(() {
      _attempt++;
      _progress = 0;
      _state = _LoadState.loading;
    });
    _startTimeout();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.document.title),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Cerrar',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        bottom: _state == _LoadState.loading
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(
                  value: _progress > 0 ? _progress / 100 : null,
                  minHeight: 3,
                ),
              )
            : null,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            // La página se mantiene montada (aunque tape el error) para que
            // pueda terminar de cargar; el error se dibuja encima.
            Positioned.fill(
              child: Offstage(
                offstage: _state == _LoadState.error,
                child: KeyedSubtree(
                  key: ValueKey<int>(_attempt),
                  child: widget.pageBuilder(
                    context,
                    widget.document.uri,
                    LegalPageCallbacks(
                      onProgress: _onProgress,
                      onLoaded: _onLoaded,
                      onError: _onError,
                      onExternalLink: _openExternal,
                    ),
                  ),
                ),
              ),
            ),
            if (_state == _LoadState.loading)
              Positioned.fill(
                child: ColoredBox(
                  color: theme.colorScheme.surface,
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
            if (_state == _LoadState.error)
              Positioned.fill(
                child: ColoredBox(
                  color: theme.colorScheme.surface,
                  child: _ErrorView(
                    onRetry: _retry,
                    onOpenBrowser: () => _openExternal(widget.document.uri),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry, required this.onOpenBrowser});

  final VoidCallback onRetry;
  final VoidCallback onOpenBrowser;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 40, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              'No pudimos cargar este documento.',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Revisa tu conexión e inténtalo de nuevo, o ábrelo en el navegador.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
            const SizedBox(height: 8),
            TextButton(onPressed: onOpenBrowser, child: const Text('Abrir en el navegador')),
          ],
        ),
      ),
    );
  }
}
