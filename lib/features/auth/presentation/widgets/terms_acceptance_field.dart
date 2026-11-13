import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../domain/legal_terms.dart';
import '../legal_document_screen.dart';

/// Abre un documento legal. Por defecto, la ventana modal integrada.
typedef LegalDocumentOpener = Future<void> Function(
  BuildContext context,
  LegalDocument document,
);

Future<void> _defaultOpener(BuildContext context, LegalDocument document) {
  return showLegalDocument(context, document);
}

/// Casilla de consentimiento (Términos + tratamiento de datos) del registro.
///
/// Sobria, al estilo de las apps de transporte: texto pequeño con los dos
/// documentos resaltados y la casilla a la izquierda. Nace SIN marcar. Esta
/// pieza NO decide nada: el estado ([accepted]) vive en quien la usa, y abrir o
/// cerrar un documento nunca lo cambia.
class TermsAcceptanceField extends StatefulWidget {
  const TermsAcceptanceField({
    super.key,
    required this.accepted,
    required this.onChanged,
    this.enabled = true,
    this.opener = _defaultOpener,
  });

  final bool accepted;
  final ValueChanged<bool> onChanged;

  /// `false` mientras se envía el formulario.
  final bool enabled;

  /// Se puede reemplazar en pruebas para no abrir la ventana real.
  final LegalDocumentOpener opener;

  @override
  State<TermsAcceptanceField> createState() => _TermsAcceptanceFieldState();
}

class _TermsAcceptanceFieldState extends State<TermsAcceptanceField> {
  late final TapGestureRecognizer _termsTap;
  late final TapGestureRecognizer _privacyTap;

  @override
  void initState() {
    super.initState();
    _termsTap = TapGestureRecognizer()..onTap = () => _open(LegalDocument.terms);
    _privacyTap = TapGestureRecognizer()..onTap = () => _open(LegalDocument.privacy);
  }

  @override
  void dispose() {
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  // Abrir un documento NO toca la casilla.
  Future<void> _open(LegalDocument document) => widget.opener(context, document);

  void _toggle() {
    if (widget.enabled) {
      widget.onChanged(!widget.accepted);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      height: 1.4,
    );
    final linkStyle = baseStyle?.copyWith(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: theme.colorScheme.primary,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          value: widget.accepted,
          onChanged: widget.enabled ? (v) => widget.onChanged(v ?? false) : null,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggle,
              child: Text.rich(
                TextSpan(
                  style: baseStyle,
                  children: [
                    const TextSpan(text: 'Acepto los '),
                    TextSpan(
                      text: LegalDocument.terms.title,
                      style: linkStyle,
                      recognizer: _termsTap,
                    ),
                    const TextSpan(
                      text: ' y autorizo el tratamiento de mis datos personales conforme a la ',
                    ),
                    TextSpan(
                      text: LegalDocument.privacy.title,
                      style: linkStyle,
                      recognizer: _privacyTap,
                    ),
                    const TextSpan(text: '.'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
