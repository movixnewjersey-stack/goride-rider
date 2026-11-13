import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import 'chat_controller.dart';

final chatControllerProvider = StateNotifierProvider.autoDispose.family<ChatController, ChatState, int>((ref, bookingId) {
  return ChatController(
    bookingId: bookingId,
    trips: ref.watch(tripRepositoryProvider),
    chat: ref.watch(chatRepositoryProvider),
  );
});
