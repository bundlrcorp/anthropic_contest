import 'dart:async';
import 'dart:convert';
import 'package:bloc/bloc.dart';
import 'package:bundlr/core/common/extension/stream_future_extensions.dart';
import 'package:bundlr/core/di/di_provider.dart';
import 'package:bundlr/core/interfaces/podcast_player_interface.dart';
import 'package:bundlr/core/model/bundle_content.dart';
import 'package:bundlr/core/model/knowledge_objects/knowledge_object.dart';
import 'package:bundlr/core/model/ko_type_enum.dart';
import 'package:bundlr/core/model/subscribe_dialog_actions.dart';
import 'package:bundlr/core/model/subscribe_status.dart';
import 'package:bundlr/core/model/transcription_feedback.dart';
import 'package:bundlr/core/model/transcription_new.dart';
import 'package:bundlr/core/repository/feed_repository.dart';
import 'package:bundlr/core/repository/podcast_repository.dart';
import 'package:bundlr/ui/profile/common/route_observer.dart';
import 'package:bundlr/ui/profile/common/stopwatch_provider.dart';
import 'package:bundlr/ui/router/app_router.dart';
import 'package:bundlr/ui/common/subscribe_base_cubit/subscribe_base_cubit.dart';
import 'package:bundlr/ui/section/error_handler/error_handler_cubit.dart';
import 'package:dartx/dartx.dart';
import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:bundlr/core/model/transcription.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bundlr/core/source/ai_remote_source.dart';
import 'package:bundlr/core/source/podcast_remote_source.dart';
import 'package:bundlr/ui/ko_chat/ko_chat_cubit.dart';

part 'podcast_player_cubit.freezed.dart';

part 'podcast_player_state.dart';

class PodcastPlayerCubit extends Cubit<PodcastPlayerState>
    with SubscribeBaseCubit<PodcastPlayerState> {
  final FeedRepository _feedRepository = DiProvider.get<FeedRepository>();
  final PodcastRepository _podcastRepository =
      DiProvider.get<PodcastRepository>();
  final PodcastRemoteSource _podcastRemoteSource =
      DiProvider.get<PodcastRemoteSource>();
  late final StreamSubscription<Duration> _currentPositionSubscription;
  late final StreamSubscription<Duration?> _totalDurationSubscription;
  late final StreamSubscription<PlayerState> _playerStateSubscription;
  late final StreamSubscription<double> _playerSpeedSubscription;
  final AiRemoteSource _aiRemoteSource = AiRemoteSource();

  @override
  L3KnowledgeObject? knowledgeObject;
  @override
  AppRouter router = DiProvider.get();
  bool? isDeepLink;
  final ErrorHandlerCubit _errorHandler;
  final Duration? timeStamp;
  ValueNotifier<PlayerState>? playing = ValueNotifier(PlayerState.stop);

  PodcastPlayerCubit(
    this.knowledgeObject,
    this.isDeepLink,
    this._errorHandler,
    this.timeStamp,
  ) : super(
          PodcastPlayerState.state(
            generating: false,
            isAvailable: knowledgeObject?.available ?? true,
            activeEpisode: false,
            podcast: knowledgeObject,
            podcastCurrentPosition: Duration(
              seconds: timeStamp != null
                  ? timeStamp.inSeconds
                  : knowledgeObject?.playedAt?.toInt() ?? 0,
              milliseconds: timeStamp != null
                  ? (timeStamp.inMilliseconds % 1000).toInt()
                  : knowledgeObject?.playedAt?.remainder(1).toInt() ?? 0,
            ),
            podcastDuration: Duration(
              seconds: knowledgeObject?.duration?.toInt() ?? 1,
              milliseconds:
                  knowledgeObject?.duration?.remainder(1).toInt() ?? 0,
            ),
            playSpeed: 1,
            descriptionExpanded: false,
            isListenedTo: knowledgeObject?.listened ?? false,
            isLiked: knowledgeObject?.liked ?? false,
            subscribeStatus: SubscribeStatus.pending(),
            action: SubscribeDialogAction.idle(),
            isLoading: false,
            fullPlayerVisible: false,
            transcriptionsTimestamped: [],
            transcriptionFeedback: null,
            chatMessages: null,
            transcriptionPrompt: null,
            transcriptionFocused: true,
            transcriptionRowVisible: false,
          ),
        ) {
    initialize();
  }

  
  }

  Future<void> getTopics(TranscriptionPrompt? prompt) async {
    emit(state.copyWith(generating: true));
    emit(state.copyWith(transcriptionFeedback: null));
    final transcriptions = state.transcriptionsTimestamped;
    final finalString = transcriptions
            // ignore: lines_longer_than_80_chars
            ?.map(
              (transcription) =>
                  '${transcription.start?.toStringAsFixed(2)}s: ${transcription.text?.trim()}',
            )
            .join('\n\n') ??
        '';

    final List<Message> userMessage = [
      Message(
        content: [
          {
            'type': 'text',
            'text': prompt?.userPrompt ?? 'prompt2',
          }
        ] as dynamic,
        role: "user",
      ),
    ];
    Stream<Map<String, dynamic>?> response;
    response = _aiRemoteSource.getChatResponseStream(
      model: prompt?.modelName ?? '',
      maxTokens: prompt?.maxTokens.toInt() ?? 0,
      temperature: prompt?.temperature ?? 0,
      prompt?.systemPrompt ?? 'formatSystemMessage() + finalString,',
      userMessage,
    )..listen((event) {
        String? extractedText;
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
      }).onDone(() {
        _saveHighlights();
        if (!isClosed) {
          emit(state.copyWith(generating: false));
        }
      });
  }
}
