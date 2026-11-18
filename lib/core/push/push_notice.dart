import 'package:flutter/material.dart';

/// Texto de un aviso recibido con la app abierta.
class PushNotice {
  const PushNotice({required this.title, required this.body});

  final String title;
  final String body;

  bool get isEmpty => title.isEmpty && body.isEmpty;
}

/// Permite mostrar un aviso encima de cualquier pantalla.
final GlobalKey<ScaffoldMessengerState> rootMessengerKey = GlobalKey<ScaffoldMessengerState>();

void showPushNotice(PushNotice notice) {
  if (notice.isEmpty) {
    return;
  }
  final messenger = rootMessengerKey.currentState;
  if (messenger == null) {
    return;
  }
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (notice.title.isNotEmpty) Text(notice.title, style: const TextStyle(fontWeight: FontWeight.bold)),
            if (notice.body.isNotEmpty) Text(notice.body, maxLines: 3, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
}
