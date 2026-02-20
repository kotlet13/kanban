import 'dart:convert';

import 'package:http/http.dart' as http;

import '../storage/ai_settings_store.dart';
import 'ai_models.dart';
import 'ai_provider.dart';

class OpenAiLocalProvider implements AiProvider {
  OpenAiLocalProvider({
    required this.httpClient,
    required this.readSettings,
  });

  final http.Client httpClient;
  final Future<AiSettings> Function() readSettings;

  @override
  Stream<String> streamChat({
    required List<AiChatMessage> history,
    required String userPrompt,
  }) async* {
    final settings = await readSettings();
    if (!settings.enabled) {
      throw StateError('AI is disabled in settings.');
    }
    final apiKey = settings.apiKey?.trim() ?? '';
    if (apiKey.isEmpty) {
      throw StateError('OpenAI API key is missing.');
    }

    final request = http.Request(
      'POST',
      Uri.parse('https://api.openai.com/v1/responses'),
    );
    request.headers.addAll(<String, String>{
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
    });
    request.body = jsonEncode(
      _requestPayload(
        model: settings.model.trim(),
        systemPrompt:
            'You are a concise assistant inside a Kanboard Flutter app. Keep answers practical and short.',
        input: _buildChatInput(history: history, userPrompt: userPrompt),
        thinkingMode: settings.isThinkingMode,
        thinkingEffort: settings.normalizedThinkingEffort,
        stream: true,
      ),
    );

    final response = await httpClient.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final rawBody = await response.stream.bytesToString();
      throw Exception(
        'OpenAI request failed (${response.statusCode}): ${rawBody.trim()}',
      );
    }

    var eventType = '';
    final dataLines = <String>[];
    await for (final line in response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (line.isEmpty) {
        if (dataLines.isNotEmpty) {
          final payload = dataLines.join('\n').trim();
          dataLines.clear();
          if (payload == '[DONE]') continue;
          late final Map<String, dynamic> decoded;
          try {
            decoded = jsonDecode(payload) as Map<String, dynamic>;
          } catch (_) {
            // ignore malformed event payloads
            continue;
          }
          final chunk = _extractStreamDelta(decoded, eventType);
          if (chunk != null && chunk.isNotEmpty) {
            yield chunk;
          }
        }
        eventType = '';
        continue;
      }
      if (line.startsWith('event:')) {
        eventType = line.substring('event:'.length).trim();
        continue;
      }
      if (line.startsWith('data:')) {
        dataLines.add(line.substring('data:'.length).trimLeft());
      }
    }
  }

  @override
  Future<String> sendChat({
    required List<AiChatMessage> history,
    required String userPrompt,
  }) async {
    final buffer = StringBuffer();
    await for (final delta in streamChat(
      history: history,
      userPrompt: userPrompt,
    )) {
      buffer.write(delta);
    }
    final text = buffer.toString().trim();
    if (text.isEmpty) {
      throw Exception('OpenAI returned an empty response.');
    }
    return text;
  }

  @override
  Future<String> assistTaskTitle(AiTaskAssistRequest request) {
    return _complete(
      systemPrompt:
          'Rewrite task titles to be clear, actionable, and concise. Return title only.',
      input:
          'Project: ${request.projectName}\nCurrent title: ${request.title}\nDescription: ${request.description}',
    );
  }

  @override
  Future<String> assistTaskDescription(AiTaskAssistRequest request) {
    return _complete(
      systemPrompt:
          'Rewrite task descriptions for clarity. Keep structure with short paragraphs and bullet points when useful.',
      input:
          'Project: ${request.projectName}\nTitle: ${request.title}\nCurrent description: ${request.description}',
    );
  }

  Future<String> _complete({
    required String systemPrompt,
    required String input,
  }) async {
    final settings = await readSettings();
    if (!settings.enabled) {
      throw StateError('AI is disabled in settings.');
    }
    final apiKey = settings.apiKey?.trim() ?? '';
    if (apiKey.isEmpty) {
      throw StateError('OpenAI API key is missing.');
    }

    final response = await httpClient.post(
      Uri.parse('https://api.openai.com/v1/responses'),
      headers: <String, String>{
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(
        _requestPayload(
          model: settings.model.trim(),
          systemPrompt: systemPrompt,
          input: input,
          thinkingMode: settings.isThinkingMode,
          thinkingEffort: settings.normalizedThinkingEffort,
        ),
      ),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('OpenAI request failed (${response.statusCode}).');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final outputText = decoded['output_text']?.toString().trim();
    if (outputText != null && outputText.isNotEmpty) return outputText;

    final output = decoded['output'];
    if (output is List) {
      for (final item in output) {
        if (item is! Map<String, dynamic>) continue;
        final content = item['content'];
        if (content is! List) continue;
        for (final chunk in content) {
          if (chunk is! Map<String, dynamic>) continue;
          final text = chunk['text']?.toString().trim();
          if (text != null && text.isNotEmpty) return text;
        }
      }
    }
    throw Exception('OpenAI returned an empty response.');
  }

  String _buildChatInput({
    required List<AiChatMessage> history,
    required String userPrompt,
  }) {
    final historyBlock = history
        .map((m) => '${m.role.toUpperCase()}: ${m.content}')
        .join('\n');
    return historyBlock.isEmpty ? userPrompt : '$historyBlock\nUSER: $userPrompt';
  }

  Map<String, dynamic> _requestPayload({
    required String model,
    required String systemPrompt,
    required String input,
    bool thinkingMode = false,
    String thinkingEffort = 'medium',
    bool stream = false,
  }) {
    return <String, dynamic>{
      'model': model,
      'input': input,
      'instructions': systemPrompt,
      if (thinkingMode)
        'reasoning': <String, dynamic>{'effort': thinkingEffort},
      if (stream) 'stream': true,
    };
  }

  String? _extractStreamDelta(Map<String, dynamic> event, String eventType) {
    final type = event['type']?.toString() ?? eventType;
    if (type == 'response.output_text.delta') {
      return event['delta']?.toString();
    }
    if (type == 'response.error' || type == 'error') {
      final message = event['message']?.toString();
      if (message != null && message.isNotEmpty) {
        throw Exception(message);
      }
    }
    final delta = event['delta']?.toString();
    if (delta != null && delta.isNotEmpty) return delta;
    return null;
  }
}
