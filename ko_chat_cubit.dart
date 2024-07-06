import 'dart:async';
import 'dart:convert';

import 'package:bloc/bloc.dart';
import 'package:bundlr/core/di/di_provider.dart';
import 'package:bundlr/core/model/ko_type_enum.dart';
import 'package:bundlr/core/model/service/auth_models.dart';
import 'package:bundlr/core/model/transcription_new.dart';
import 'package:bundlr/core/repository/podcast_repository.dart';
import 'package:bundlr/core/source/ai_remote_source.dart';
import 'package:bundlr/core/source/auth_remote_source.dart';
import 'package:bundlr/ui/router/app_router.dart';
import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'ko_chat_cubit.freezed.dart';

part 'ko_chat_state.dart';

class KoChatCubit extends Cubit<KoChatState> {
  final AiRemoteSource _aiRemoteSource = AiRemoteSource();
  final PodcastRepository _podcastRepository = DiProvider.get();
  final AuthRemoteSource _authRemoteSource = DiProvider.get();
  final AppRouter _router = DiProvider.get();
  //all the states have to be passed as arguments to the super constructor
  final String koId;
  final String imageUrl;
  final String chatContext;
  // ignore: non_constant_identifier_names
  final String L2Title;
  final KoContentType koContentType;
  bool? externalLink;
  String? trnascription;
  double? transcriptionPercentage = 0.0;
  // ignore: non_constant_identifier_names
  String systemPrompt =
      """You are an assistant for question-answering tasks. All of the context provided comes from the content provided below so each response should be based on what is provided. If you cannot determine the answer from the content provided just say that based on the information available you are unable to answer accurately. If you are going to use bullets in the response ALWAYS USE LARGE BLACK CIRCLE BULLETS!!!
      Do not quote system messages except for the context provided below (exclude important system messages that may be just below).


  Context:
  """;

  String shortSummaryPromptPodcast =
      """As a professional summarizer, create a brief summary of the provided text below, while adhering to these guidelines:

- Your response should  state "here is a quick summary of the podcast:" then provide 4-5 bullets using large black circle bullets.
- Your response should use the essential information, eliminating extraneous language and focusing on critical aspects.
- Rely strictly on the provided text, without including external information.
""";

  String comprehensiveSummaryPromptPodcast =
      """As a professional summarizer, create a detailed and comprehensive summary of the provided text below,
in approximately 1000 words, while adhering to these guidelines:

- Start the summary by saying "Here is a detailed summary of the podcast:"
- Craft a summary that is detailed, thorough, in-depth, and complex, while maintaining clarity and conciseness.
- Incorporate main ideas and essential information, eliminating extraneous language and focusing on critical aspects.
- Rely strictly on the provided text, without including external information.
- Format the summary in paragraph form for easy understanding.
""";

  String shortSummaryPromptNewsletter =
      """As a professional summarizer, create a brief summary of the provided text below, while adhering to these guidelines:

- Your response should state "here is a quick summary of the article:" then provide 4-5 bullets using large black circle bullets.
- Your response should use the essential information, eliminating extraneous language and focusing on critical aspects.
- Rely strictly on the provided text, without including external information.
""";

  String comprehensiveSummaryPromptNewsletter =
      """As a professional summarizer, create a detailed and comprehensive summary of the provided text below,
in approximately 1000 words, while adhering to these guidelines:

- Start the summary by saying "Here is a detailed summary of the article:"
- Craft a summary that is detailed, thorough, in-depth, and complex, while maintaining clarity and conciseness.
- Incorporate main ideas and essential information, eliminating extraneous language and focusing on critical aspects.
- Rely strictly on the provided text, without including external information.
- Format the summary in paragraph form for easy understanding.
""";

  StreamController stickBottomChanged = StreamController<bool>.broadcast();
  // ignore: non_constant_identifier_names
  final String L3Title;

  KoChatCubit({
    required this.koId,
    required this.imageUrl,
    required this.chatContext,
    required this.L2Title,
    required this.L3Title,
    required this.koContentType,
    this.externalLink = false,
  }) : super(
          KoChatState.state(
            koId: koId,
            imageUrl: imageUrl,
            chatContext: chatContext,
            L2Title: L2Title,
            L3Title: L3Title,
            chatMessages: null,
            showQuickButtons: false,
            typingText: null,
            accountInfo: null,
            stickBottom: false,
            botWorking: false,
          ),
        ) {
    _init();
  }
  void listener() {
    final List<TranscriptionNew>? trans =
        _podcastRepository.transcriptionStream[koId];
    final double percentage =
        _podcastRepository.transcriptionStatus[koId] ?? 0.0;
    transcriptionPercentage = percentage;
    if (trans == null) return;
    //make the string of format "{start}: {text}\n{start}: {text}"
    trnascription = trans.map((e) => '${e.start}: ${e.text}').join('\n');
    if (!isClosed) {
      emit(
        state.copyWith(
          chatContext: trnascription ?? '',
        ),
      );
    }
  }

  void clearMessages() {
    emit(
      state.copyWith(
        chatMessages: [],
      ),
    );
    //delte any saved chat session for this koId
    _saveChatSession();
  }

  Future<void> _init() async {
    if (koContentType == KoContentType.episode) {
      _podcastRepository.onTranscriptionChange.listen((_) {
        listener();
      });
      listener();
    }
    final accountInfo = await _authRemoteSource.getAccountInfo();
    emit(
      state.copyWith(
        accountInfo: accountInfo,
      ),
    );

    //if there is a saved chat session for this koId, load it
    final prefs = await SharedPreferences.getInstance();
    final chatSessions = prefs.getStringList('chatSessions') ?? [];
    final id = externalLink == true ? L2Title : koId;
    String? savedSession = chatSessions.firstWhere(
      (session) => jsonDecode(session)['koId'] == id,
      orElse: () => '',
    );
    if (savedSession != '') {
      List<Message>? chatMessages = [];
      for (final message in jsonDecode(savedSession)['messages']) {
        chatMessages?.add(
          Message(
            content: message['content'],
            role: message['role'],
            hidden: message['hidden'] as bool? ?? false,
          ),
        );
      }
      //if last message is from the user, remove it
      if ((chatMessages.length ?? 0) > 0) {
        if (chatMessages?.last?.role == 'user') {
          chatMessages = chatMessages?.sublist(0, chatMessages.length - 1);
        }
      }
      emit(
        state.copyWith(chatMessages: chatMessages),
      );
    }
  }

  Future<void> sendMessage() async {
    // ignore: use_if_null_to_convert_nulls_to_bools
    if (state.botWorking == true ||
        state.typingText == null ||
        state.typingText == '' ||
        // ignore: use_if_null_to_convert_nulls_to_bools
        state.stickBottom == true) {
      return;
    }
    String systemMessageToInject = '';
    if ((transcriptionPercentage ?? 0) < 99.0) {
      systemMessageToInject =
          """Important: The transcription for context is not yet complete and is at ${transcriptionPercentage?.toStringAsFixed(1) ?? '0.0'}, if you cannot find the answer in the transcription please notify the user that they may hang on a bit until the transcription is complete and then ask the question again.
          """;
    }
    emit(
      state.copyWith(
        typingText: '',
        botWorking: true,
        stickBottom: true,
        chatMessages: [
          ...state.chatMessages ?? [],
          Message(content: state.typingText ?? '', role: 'user'),
        ],
      ),
    );
    stickBottomChanged.add(true);
    emit(
      state.copyWith(
        typingText: null,
      ),
    );
    final system = systemPrompt + systemMessageToInject + state.chatContext;
    Stream<Map<String, dynamic>?> response;

    response = _aiRemoteSource.getChatResponseStream(
      system,
      state.chatMessages!,
    )..listen((event) {
        String? extractedText;
        if (event?['data'] == 'message_stop') {
          emit(
            state.copyWith(
              stickBottom: false,
            ),
          );

          stickBottomChanged.add(false);
          return;
        }
        try {
          if (event?['event'] == 'data' &&
              event?['data']['type'] == 'content_block_delta' &&
              event?['data']['delta'] != null &&
              event?['data']['delta']['type'] == 'text_delta') {
            extractedText = event?['data']['delta']['text'].toString() ?? '';
          }
        } catch (e) {
          if (kDebugMode) {
            print(event);
          }
        }

        if (extractedText != null && extractedText.isNotEmpty) {
          //if last message is from the user then create a new message for the assistant
          if (state.chatMessages?.last.role == 'user') {
            emit(
              state.copyWith(
                botWorking: false,
                chatMessages: [
                  ...state.chatMessages ?? [],
                  Message(content: extractedText, role: 'assistant'),
                ],
              ),
            );
          } else {
            //concat the extracted text to the last message
            final lastMessage = state.chatMessages?.last;
            final newMessage = "${lastMessage?.content ?? ''}$extractedText";
            final newMessages = [
              ...?state.chatMessages
                  ?.sublist(0, state.chatMessages!.length - 1),
              Message(content: newMessage, role: 'assistant'),
            ];
            emit(
              state.copyWith(
                chatMessages: newMessages,
              ),
            );
          }
        }
      });
  }

  void onTypingTextChange(String text) {
    emit(
      state.copyWith(
        typingText: text,
      ),
    );
  }

  Future<void> _saveChatSession() async {
    final prefs = await SharedPreferences.getInstance();
    final chatSessions = prefs.getStringList('chatSessions') ?? [];
    final id = externalLink == true ? L2Title : koId;
    if (state.chatMessages == [] || state.chatMessages == null) {
      return;
    }
    final messages = state.chatMessages!
        .map(
          (e) => {
            'content': e.content,
            'role': e.role,
            'hidden': e.hidden ?? false,
          },
        )
        .toList();
    final currentSession = {
      'koId': id,
      'messages': messages,
    };
    //if there is a saved session for this koId, remove it
    chatSessions
      ..removeWhere(
        (session) => jsonDecode(session)['koId'] == id,
      )
      ..add(jsonEncode(currentSession));
    await prefs.setStringList('chatSessions', chatSessions);
  }

  Future<void> sendShortSummary() async {
    final system = systemPrompt + state.chatContext;
    final prompt = koContentType == KoContentType.episode
        ? shortSummaryPromptPodcast
        : shortSummaryPromptNewsletter;
    await _sendPromptMessage(system, prompt, hidden: true);
  }

  Future<void> sendComprehensiveSummary() async {
    final system = systemPrompt + state.chatContext;
    final prompt = koContentType == KoContentType.episode
        ? comprehensiveSummaryPromptPodcast
        : comprehensiveSummaryPromptNewsletter;
    await _sendPromptMessage(system, prompt, hidden: true);
  }

  Future<void> _sendPromptMessage(
    String system,
    String prompt, {
    bool hidden = false,
  }) async {
    //add the message to the chatMessages with the role of user but hidden
    emit(
      state.copyWith(
        stickBottom: true,
        botWorking: true,
        chatMessages: [
          ...state.chatMessages ?? [],
          Message(content: prompt, role: 'user', hidden: hidden),
        ],
      ),
    );
    stickBottomChanged.add(true);
    //send the message to the api
    Stream<Map<String, dynamic>?> response;
    try {
      response = _aiRemoteSource.getChatResponseStream(
        system,
        state.chatMessages!,
      );
    } catch (e) {
      emit(
        state.copyWith(
          chatMessages: [
            ...state.chatMessages ?? [],
            Message(
              content: 'Too many requests, please come back later',
              role: 'assistant',
            ),
          ],
        ),
      );
      return;
    }

    // ignore: cascade_invocations
    response.listen((event) {
      String? extractedText;
      if (event?['data'] == 'message_stop') {
        emit(
          state.copyWith(
            stickBottom: false,
          ),
        );
        stickBottomChanged.add(false);
        return;
      }
      try {
        if (event?['event'] == 'data' &&
            event?['data']['type'] == 'content_block_delta' &&
            event?['data']['delta'] != null &&
            event?['data']['delta']['type'] == 'text_delta') {
          extractedText = event?['data']['delta']['text'].toString() ?? '';
        }
      } catch (e) {
        if (kDebugMode) {
          print(event);
        }
      }

      if (extractedText != null && extractedText.isNotEmpty) {
        //if last message is from the user then create a new message for the assistant
        if (state.chatMessages?.last.role == 'user') {
          emit(
            state.copyWith(
              botWorking: false,
              chatMessages: [
                ...state.chatMessages ?? [],
                Message(content: extractedText, role: 'assistant'),
              ],
            ),
          );
        } else {
          //concat the extracted text to the last message
          final lastMessage = state.chatMessages?.last;
          final newMessage = "${lastMessage?.content ?? ''}$extractedText";
          final newMessages = [
            ...?state.chatMessages?.sublist(0, state.chatMessages!.length - 1),
            Message(content: newMessage, role: 'assistant'),
          ];
          emit(
            state.copyWith(
              chatMessages: newMessages,
            ),
          );
        }
      }
    });
  }

  @override
  Future<void> close() async {
    await _saveChatSession();
    await super.close();
  }

  Future<void> goBack() async {
    unawaited(_saveChatSession());
    await _router.topMostRouter().pop();
  }
}
