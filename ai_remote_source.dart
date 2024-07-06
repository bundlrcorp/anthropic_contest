import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:bundlr/ui/ko_chat/ko_chat_cubit.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';

class AiRemoteSource {
  final dio = Dio();
  static const chatUrl = "https://api.anthropic.com/v1/messages";
  static const aiToken =
      "ANTHROPIC_API_KEY_HERE";

  AiRemoteSource();

  Stream<Map<String, dynamic>?> getChatResponseStream(
    String systemPrompt,
    List<Message> messages, {
    String? model = "claude-3-haiku-20240307",
    int? maxTokens = 4096,
    double? temperature = 0.3,
  }) async* {
    try {
      final response = await dio.post(
        chatUrl,
        data: jsonEncode({
          "model": model,
          "messages": messages
              .map(
                (e) => {
                  "role": e.role,
                  "content": e.content,
                },
              )
              .toList(),
          "system": systemPrompt,
          "temperature": temperature,
          "max_tokens": maxTokens,
          "stream": true, // Enable streaming
        }),
        options: Options(
          headers: {
            "x-api-key": aiToken,
            "content-type": "application/json",
            "anthropic-version": "2023-06-01",
            "anthropic-beta": "messages-2023-12-15", // Required for streaming
          },
          responseType: ResponseType.stream, // Receive response as a stream
        ),
      );
      await for (final chunk in response.data.stream) {
        final lines = utf8.decode(chunk).split('\n');
        for (final line in lines) {
          if (line.isNotEmpty && line.contains(': ')) {
            //split only on first occurence of ': ' to avoid splitting on the content
            final parts = line.split(': ');
            final event = parts[0].trim();
            for (var i = 1; i < parts.length - 1; i++) {
              parts[i] += ': ${parts.removeAt(i + 1)}';
            }
            final dataString = parts[1].trim();

            // Check if data is a simple string or a dictionary
            dynamic data;
            if (dataString.startsWith('{') && dataString.endsWith('}')) {
              // Parse as JSON
              data = jsonDecode(dataString);
            } else {
              // Treat as a simple string
              data = dataString;
            }
            yield {'event': event, 'data': data};
          }
        }
      }
    } on DioException catch (e) {
      // Handle the DioError here
      if (e.response != null) {
        // Handle the HTTP status code and response body
        if (kDebugMode) {
          print('Error: ${e.response!.statusCode} - ${e.response!.data}');
        }
      } else {
        // Handle other types of errors
        if (kDebugMode) {
          print('Error: ${e.message}');
        }
      }
    }
  }
}
