import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/providers.dart';
import 'widgets/terms_acceptance_field.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();

  // El consentimiento NACE sin marcar y solo lo cambia el usuario.
  bool _accepted = false;
  bool _busy = false;
  bool _showTermsError = false;
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) {
      return;
    }
    final valid = _form.currentState?.validate() ?? false;
    if (!_accepted) {
      setState(() => _showTermsError = true);
    }
    if (!valid || !_accepted) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await ref.read(authRepositoryProvider).register(
            firstName: _first.text.trim(),
            lastName: _last.text.trim(),
            email: _email.text.trim(),
            phone: _phone.text.trim(),
            password: _password.text,
            termsAccepted: _accepted,
          );
      await ref.read(sessionControllerProvider.notifier).signIn(session);
    } catch (e) {
      if (mounted) {
        setState(() => _error = userMessage(e));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  String? _required(String? v, String what) => (v ?? '').trim().isEmpty ? 'Escribe $what' : null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crear cuenta'),
        leading: BackButton(onPressed: _busy ? null : () => context.go('/login')),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _first,
                  enabled: !_busy,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                  validator: (v) => _required(v, 'tu nombre'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _last,
                  enabled: !_busy,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Apellido'),
                  validator: (v) => _required(v, 'tu apellido'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _email,
                  enabled: !_busy,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Correo electrónico'),
                  validator: (v) {
                    final t = (v ?? '').trim();
                    return t.contains('@') && t.contains('.') ? null : 'Escribe un correo válido';
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phone,
                  enabled: !_busy,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Teléfono',
                    helperText: 'Tu conductor podrá usarlo para ubicarte.',
                  ),
                  validator: (v) {
                    final digits = (v ?? '').replaceAll(RegExp(r'[^0-9]'), '');
                    return digits.length >= 7 ? null : 'Escribe un teléfono válido';
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _password,
                  enabled: !_busy,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Contraseña'),
                  validator: (v) => (v ?? '').length >= 8 ? null : 'Mínimo 8 caracteres',
                ),
                const SizedBox(height: 16),
                TermsAcceptanceField(
                  accepted: _accepted,
                  enabled: !_busy,
                  onChanged: (v) => setState(() {
                    _accepted = v;
                    if (v) {
                      _showTermsError = false;
                    }
                  }),
                ),
                if (_showTermsError)
                  Padding(
                    padding: const EdgeInsets.only(left: 12, top: 4),
                    child: Text(
                      'Debes aceptar los términos para crear tu cuenta.',
                      key: const Key('terms_error'),
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: TextStyle(color: theme.colorScheme.error), key: const Key('register_error')),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  key: const Key('register_submit'),
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Crear cuenta'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
