// ignore_for_file: non_constant_identifier_names, lines_longer_than_80_chars, library_private_types_in_public_api

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:bundlr/core/common/extension/string_extensions.dart';
import 'package:bundlr/core/model/ko_type_enum.dart';
import 'package:bundlr/gen/assets.gen.dart';
import 'package:bundlr/ui/extensions/context_extensions.dart';
import 'package:bundlr/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:bundlr/ui/ko_chat/ko_chat_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';

@RoutePage(name: 'KoChat')
class KoChatScreen extends StatelessWidget {
  final String koId;
  final String imageUrl;
  final String chatContext;
  final String L2Title;
  final String L3Title;
  final KoContentType koContentType;

  const KoChatScreen({
    required this.koId,
    required this.imageUrl,
    required this.chatContext,
    required this.L2Title,
    required this.L3Title,
    required this.koContentType,
    super.key,
  });

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (_) => KoChatCubit(
          koId: koId,
          imageUrl: imageUrl,
          chatContext: chatContext,
          L2Title: L2Title,
          L3Title: L3Title,
          koContentType: koContentType,
        ),
        child: _KoChatScreen(),
      );
}

class _KoChatScreen extends StatefulWidget {
  @override
  State<_KoChatScreen> createState() => _KoChatScreenState();
}

class _KoChatScreenState extends State<_KoChatScreen> {
  @override
  Widget build(BuildContext context) => BlocBuilder<KoChatCubit, KoChatState>(
        builder: (context, state) => Scaffold(
          appBar: AppBar(
            surfaceTintColor: Colors.transparent,
            automaticallyImplyLeading: false,
            flexibleSpace: SafeArea(
              child: Row(
                children: [
                  // Back button aligned to the start
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => context.read<KoChatCubit>().goBack(),
                  ),

                  // Empty space to push the title to the center
                  const Spacer(),

                  // Star icon positioned halfway between the back button and title
                  Padding(
                    padding: const EdgeInsets.only(
                      right: 16.0,
                    ), // Adjust padding as needed
                    child: Assets.icons.starsAi.svg(
                      width: 22.w,
                      height: 22.h,
                    ),
                  ),

                  // Title in the center
                  const Text(
                    'Bundlr chat',
                    style:
                        TextStyle(fontSize: 20.0, fontWeight: FontWeight.w500),
                  ),

                  // Empty space to push the clear button to the end
                  const Spacer(),

                  // Clear button aligned to the end
                  QuickButtonStyleButton(
                    onTap: () => context.read<KoChatCubit>().clearMessages(),
                    title: 'Clear chat',
                  ),
                ],
              ),
            ),
          ),
          body: const ChatMessagesArea(),
        ),
      );
}

class ChatMessagesArea extends StatelessWidget {
  const ChatMessagesArea({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final stickBottom =
        context.select((KoChatCubit cubit) => cubit.state.stickBottom);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        const KoInfoBanner(),
        ScrollableMessagesArea(stickBottom: stickBottom),
        const TextInputArea(),
      ],
    );
  }
}

class QuickButtonStyleButton extends StatelessWidget {
  const QuickButtonStyleButton({
    required this.onTap,
    required this.title,
    super.key,
  });

  final Function() onTap;
  final String title;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.only(
            left: 15.0,
            right: 15.0,
            top: 8.0,
            bottom: 8.0,
          ),
          margin: const EdgeInsets.only(right: 8.0),
          decoration: BoxDecoration(
            color: const Color.fromRGBO(236, 231, 217, 1.0),
            borderRadius: BorderRadius.circular(8.0),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14.0,
            ),
          ),
        ),
      );
}

class KoInfoBanner extends StatelessWidget {
  const KoInfoBanner({super.key});

  @override
  Widget build(BuildContext context) => BlocBuilder<KoChatCubit, KoChatState>(
        builder: (context, state) => Container(
          margin: const EdgeInsets.all(10.0),
          padding: const EdgeInsets.all(8.0),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(3.0),
          ),
          width: MediaQuery.of(context).size.width * 0.95,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.start,
            children: <Widget>[
              Container(
                width: MediaQuery.of(context).size.width * 0.1,
                height: MediaQuery.of(context).size.width * 0.1,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16.0),
                ),
                child: Image.network(state.imageUrl, fit: BoxFit.cover),
              ),
              const SizedBox(width: 12.0),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      state.L2Title,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      state.L3Title,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class ScrollableMessagesArea extends StatefulWidget {
  const ScrollableMessagesArea({super.key, this.stickBottom});
  final bool? stickBottom;
  @override
  State<ScrollableMessagesArea> createState() => _ScrollableMessagesAreaState();
}

class _ScrollableMessagesAreaState extends State<ScrollableMessagesArea> {
  late ScrollController _scrollController;
  bool stickBottom = false; // Default value
  Timer? _stickBottomTimer;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();

    // Listen to the stream for stickBottom changes
    context.read<KoChatCubit>().stickBottomChanged.stream.listen((value) {
      setState(() {
        stickBottom = value;
      });

      if (value) {
        // Start the timer to keep the scroll glued to the bottom
        _stickBottomTimer =
            Timer.periodic(const Duration(milliseconds: 50), (_) async {
          await _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 40),
            curve: Curves.easeInOut,
          );
        });
      } else {
        // Cancel the timer to release the scroll
        _stickBottomTimer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _stickBottomTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<KoChatCubit, KoChatState>(
        builder: (context, state) => Expanded(
          child: Column(
            children: [
              Expanded(
                child: SelectionArea(
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    controller: _scrollController,
                    shrinkWrap: true,
                    itemCount: state.chatMessages?.length ?? 0,
                    itemBuilder: (context, index) {
                      final message = state.chatMessages?[index];
                      final bool isLastMessage =
                          index == state.chatMessages!.length - 1;
                      if (message?.hidden ?? false) {
                        if (isLastMessage && (state.botWorking ?? false)) {
                          return const BotReadingChatMessage();
                        } else {
                          return const SizedBox.shrink();
                        }
                      } else {
                        if (isLastMessage && (state.botWorking ?? false)) {
                          return Column(
                            key: Key(
                              "${state.chatMessages?.length ?? 0}${state.botWorking}",
                            ),
                            children: [
                              ChatMessage(
                                key: state.chatMessages != null
                                    ? Key("${state.chatMessages?.length ?? 0}")
                                    : null,
                                text: message?.content ?? '',
                                isUserMessage: message?.role == 'user',
                              ),
                              const BotReadingChatMessage(),
                            ],
                          );
                        } else {
                          return ChatMessage(
                            key: state.chatMessages != null
                                ? Key("${state.chatMessages?.length ?? 0}")
                                : null,
                            text: message?.content ?? '',
                            isUserMessage: message?.role == 'user',
                          );
                        }
                      }
                    },
                  ),
                ),
              ),
              if (state.chatMessages?.isEmpty ?? true) const QuickButtons(),
            ],
          ),
        ),
      );
}

class QuickButtons extends StatelessWidget {
  const QuickButtons({super.key});

  @override
  Widget build(BuildContext context) => BlocBuilder<KoChatCubit, KoChatState>(
        builder: (context, state) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            SizedBox(
              width: MediaQuery.of(context).size.width * 0.45,
              child: InkWell(
                onTap: () =>
                    context.read<KoChatCubit>().sendShortSummary(), // Add onTap
                child: Container(
                  padding: const EdgeInsets.only(
                    left: 20.0,
                    right: 20.0,
                    top: 4.0,
                    bottom: 4.0,
                  ),
                  margin: const EdgeInsets.symmetric(vertical: 24.0),
                  decoration: BoxDecoration(
                    color: const Color.fromRGBO(236, 231, 217, 1.0),
                    borderRadius: BorderRadius.circular(8.0),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      AutoSizeText(
                        'Short summary',
                        maxLines: 1,
                        maxFontSize: 16.0,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      AutoSizeText(
                        'A few quick bullets',
                        maxLines: 1,
                        maxFontSize: 15.0,
                        style: TextStyle(
                          color: Color.fromRGBO(117, 117, 117, 1),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(
              width: MediaQuery.of(context).size.width * 0.45,
              child: InkWell(
                onTap: () =>
                    context.read<KoChatCubit>().sendComprehensiveSummary(),
                child: Container(
                  padding: const EdgeInsets.only(
                    left: 20.0,
                    right: 20.0,
                    top: 4.0,
                    bottom: 4.0,
                  ), // (1
                  margin: const EdgeInsets.symmetric(vertical: 24.0),
                  decoration: BoxDecoration(
                    color: const Color.fromRGBO(236, 231, 217, 1.0),
                    borderRadius: BorderRadius.circular(8.0),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      AutoSizeText(
                        'Long summary',
                        maxLines: 1,
                        maxFontSize: 16.0,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      AutoSizeText(
                        'A longer overview',
                        maxLines: 1,
                        maxFontSize: 15.0,
                        style: TextStyle(
                          color: Color.fromRGBO(117, 117, 117, 1),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}

class ChatMessage extends StatelessWidget {
  final String text;
  final bool isUserMessage;
  final bool isLastMessage;
  const ChatMessage({
    required this.text,
    required this.isUserMessage,
    this.isLastMessage = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) => BlocBuilder<KoChatCubit, KoChatState>(
        builder: (context, state) {
          final textStyles = context.theme.textStyles;
          final colors = context.theme.colors;
          return Align(
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: MediaQuery.of(context).size.width * 0.14,
                  child: Padding(
                    padding: const EdgeInsets.only(
                      top: 7.5,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        isUserMessage
                            ? CircleAvatar(
                                radius: 18.0,
                                backgroundColor: colors.secondary.shade300,
                                child: Text(
                                  '${state.accountInfo?.firstName[0].capitalize() ?? ''}${state.accountInfo?.lastName[0].capitalize() ?? ''}',
                                  style: textStyles.headlineLarge!.copyWith(
                                    fontSize: 16.sp,
                                    color: colors.textColors.shade400,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              )
                            : CircleAvatar(
                                radius: 18.0,
                                backgroundColor: colors.secondary.shade300,
                                child: Text(
                                  "B",
                                  style: textStyles.headlineLarge!.copyWith(
                                    fontSize: 16.sp,
                                    color: colors.textColors.shade400,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                      ],
                    ),
                  ),
                ),
                Container(
                  width: MediaQuery.of(context).size.width * 0.8,
                  padding: const EdgeInsets.only(
                    left: 2.0,
                    right: 16.0,
                    top: 12.0,
                    bottom: 12.0,
                  ),
                  margin: const EdgeInsets.symmetric(
                    vertical: 2.0,
                    horizontal: 8.0,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        isUserMessage
                            ? "${state.accountInfo?.username ?? 'You'}:"
                            : "Bundlr:",
                        style: textStyles.headlineLarge!.copyWith(
                          fontSize: 16.sp,
                          color: colors.textColors.shade400,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12.0),
                      Text(
                        text,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
}

//same as chat message but insted of text it will show loader, it doesn't need any input arguments as it will be displayed only when state.readingChatMessage is true at the bottom as Bot message.
class BotReadingChatMessage extends StatelessWidget {
  const BotReadingChatMessage({super.key});

  @override
  Widget build(BuildContext context) => BlocBuilder<KoChatCubit, KoChatState>(
        builder: (context, state) {
          final textStyles = context.theme.textStyles;
          final colors = context.theme.colors;
          return Align(
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: MediaQuery.of(context).size.width * 0.14,
                  child: Padding(
                    padding: const EdgeInsets.only(
                      top: 7.5,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        CircleAvatar(
                          radius: 18.0,
                          backgroundColor: colors.secondary.shade300,
                          child: Text(
                            "B",
                            style: textStyles.headlineLarge!.copyWith(
                              fontSize: 16.sp,
                              color: colors.textColors.shade400,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  width: MediaQuery.of(context).size.width * 0.8,
                  padding: const EdgeInsets.only(
                    left: 2.0,
                    right: 16.0,
                    top: 12.0,
                    bottom: 12.0,
                  ),
                  margin: const EdgeInsets.symmetric(
                    vertical: 2.0,
                    horizontal: 8.0,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        "Bundlr:",
                        style: textStyles.headlineLarge!.copyWith(
                          fontSize: 16.sp,
                          color: colors.textColors.shade400,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12.0),
                      LoadingAnimationWidget.staggeredDotsWave(
                        size: 24.0,
                        color: Colors.black,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
}

class TextInputArea extends StatefulWidget {
  const TextInputArea({super.key});

  @override
  _TextInputAreaState createState() => _TextInputAreaState();
}

class _TextInputAreaState extends State<TextInputArea> {
  final TextEditingController _controller = TextEditingController();
  bool _isKeyboardVisible = false;
  final KeyboardVisibilityController _keyboardVisibilityController =
      KeyboardVisibilityController();
  late StreamSubscription keyboardSubscription;

  @override
  void initState() {
    super.initState();
    keyboardSubscription = _keyboardVisibilityController.onChange.listen(
      (bool visible) {
        if (mounted) {
          setState(() {
            _isKeyboardVisible = visible;
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    keyboardSubscription.cancel();
    super.dispose();
  }

  void onTapOutside(PointerDownEvent event) {
    if (_isKeyboardVisible) {
      FocusScope.of(context).unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final typingText = context.watch<KoChatCubit>().state.typingText;

    return KeyboardDismissOnTap(
      child: Container(
        decoration: BoxDecoration(
          color: const Color.fromRGBO(236, 231, 217, 1.0),
          border: Border.all(
            color: const Color.fromRGBO(202, 198, 179, 1.0),
            width: 3.0,
          ),
        ),
        padding: EdgeInsets.only(
          left: 16.0,
          right: 16.0,
          bottom: _isKeyboardVisible ? 0.0 : 28.0,
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                onTapOutside: onTapOutside,
                controller: _controller,
                style: const TextStyle(
                  fontSize: 18.0,
                  fontWeight: FontWeight.w400,
                ),
                onChanged: (value) {
                  context.read<KoChatCubit>().onTypingTextChange(value);
                },
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Ask a question',
                  hintStyle: TextStyle(
                    color: Color.fromRGBO(183, 176, 164, 1.0),
                    fontSize: 18.0,
                  ),
                ),
              ),
            ),
            IconButton(
              onPressed: () {
                context.read<KoChatCubit>().sendMessage();
                _controller.clear();
              },
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}
