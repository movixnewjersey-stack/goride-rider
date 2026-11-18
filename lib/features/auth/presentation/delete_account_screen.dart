import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/providers.dart';
import '../../trip/application/trip_providers.dart';

/// Eliminación de cuenta dentro de la app (exigida por Apple y Google Play).
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (_password.text.isEmpty) {
      setState(() => _error = 'Escribe tu contraseña para confirmar.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar tu cuenta?'),
        content: const Text('Esta acción es permanente y no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(accountRepositoryProvider).deleteAccount(password: _password.text);
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _error = e is ApiException && e.code == 'AUTH_INVALID_CREDENTIALS'
            ? 'La contraseña es incorrecta.'
            : userMessage(e);
      });
      return;
    }
    if (!mounted) {
      return;
    }
    ref.read(activeTripControllerProvider.notifier).clear();
    ref.read(requestControllerProvider.notifier).reset();
    await ref.read(pushServiceProvider).stop(unregister: true);
    final navigator = Navigator.of(context);
    await ref.read(sessionControllerProvider.notifier).signOut();
    if (navigator.mounted && navigator.canPop()) {
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Eliminar mi cuenta')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Al eliminar tu cuenta se borran tus datos personales y ya no podrás iniciar sesión. '
            'No podrás eliminarla si tienes un viaje en curso. Esta acción no se puede deshacer.',
          ),
          const SizedBox(height: 20),
          TextField(
            key: const Key('delete_password'),
            controller: _password,
            obscureText: true,
            enabled: !_busy,
            decoration: const InputDecoration(labelText: 'Contraseña', border: OutlineInputBorder()),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, key: const Key('delete_error'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            key: const Key('delete_button'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: _busy ? null : _delete,
            child: _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Eliminar mi cuenta'),
          ),
        ],
      ),
    );
  }
}
