import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../application/chat_controller.dart';
import '../application/chat_providers.dart';
import '../domain/chat_message.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.bookingId});

  final int bookingId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  int _lastCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(chatControllerProvider(widget.bookingId).notifier).start();
      }
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) {
      return;
    }
    // Se vacía el campo ANTES de enviar: un segundo toque no repite el mensaje.
    _input.clear();
    ref.read(chatControllerProvider(widget.bookingId).notifier).send(text);
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatControllerProvider(widget.bookingId));
    final controller = ref.read(chatControllerProvider(widget.bookingId).notifier);
    final theme = Theme.of(context);

    if (state.entries.length != _lastCount) {
      _lastCount = state.entries.length;
      _scrollToEnd();
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Chat con tu conductor')),
      body: Column(
        children: [
          if (state.connectionLost)
            Container(
              key: const Key('chat_connection_lost'),
              width: double.infinity,
              color: theme.colorScheme.errorContainer,
              padding: const EdgeInsets.all(8),
              child: const Text('Sin conexión. Reintentando…', textAlign: TextAlign.center),
            ),
          if (state.error != null && !state.ready)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(state.error!, textAlign: TextAlign.center),
                  TextButton(onPressed: controller.poll, child: const Text('Reintentar')),
                ],
              ),
            ),
          Expanded(
            child: state.entries.isEmpty && state.ready
                ? const Center(child: Text('Aún no hay mensajes.'))
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: state.entries.length,
                    itemBuilder: (context, i) => _Bubble(
                      entry: state.entries[i],
                      onResend: () => controller.resend(state.entries[i].key),
                      onDiscard: () => controller.discard(state.entries[i].key),
                    ),
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('chat_input'),
                      controller: _input,
                      maxLength: ChatController.maxLength,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      decoration: const InputDecoration(hintText: 'Escribe un mensaje', counterText: ''),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    key: const Key('chat_send'),
                    tooltip: 'Enviar',
                    onPressed: _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.entry, required this.onResend, required this.onDiscard});

  final ChatEntry entry;
  final VoidCallback onResend;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (entry.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Text(entry.text, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
      );
    }
    final mine = entry.isMine;
    final time = entry.time != null ? DateFormat.Hm().format(entry.time!) : '';
    final status = switch (entry.delivery) {
      ChatDelivery.sending => 'Enviando…',
      ChatDelivery.awaitingEcho => 'Enviado',
      ChatDelivery.failed => 'No se envió',
      ChatDelivery.unknown => 'No sabemos si se envió',
      ChatDelivery.sent => time,
    };
    final problem = entry.delivery == ChatDelivery.failed || entry.delivery == ChatDelivery.unknown;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: mine ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Align(alignment: Alignment.centerLeft, child: Text(entry.text)),
            const SizedBox(height: 2),
            Text(
              status,
              style: theme.textTheme.labelSmall?.copyWith(color: problem ? theme.colorScheme.error : null),
            ),
            if (problem)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(onPressed: onResend, child: Text(entry.delivery == ChatDelivery.unknown ? 'Reenviar de todos modos' : 'Reintentar')),
                  TextButton(onPressed: onDiscard, child: const Text('Descartar')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
