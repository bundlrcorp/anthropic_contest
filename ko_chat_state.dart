part of 'ko_chat_cubit.dart';

@freezed
class KoChatState with _$KoChatState {
  const factory KoChatState.state({
    required String koId,
    required String imageUrl,
    required String chatContext,
    required String L2Title,
    required String L3Title,
    AccountInfo? accountInfo,
    List<Message>? chatMessages,
    bool? showQuickButtons,
    String? typingText,
    bool? stickBottom,
    bool? botWorking,
  }) = _KoChatState;
}

class Message {
  final dynamic content;
  final String role;
  bool? hidden;

  Message({required this.content, required this.role, this.hidden = false});
}
