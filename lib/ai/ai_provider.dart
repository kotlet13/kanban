import 'ai_models.dart';

abstract class AiProvider {
  Stream<String> streamChat({
    required List<AiChatMessage> history,
    required String userPrompt,
  });

  Future<String> sendChat({
    required List<AiChatMessage> history,
    required String userPrompt,
  });

  Future<String> assistTaskTitle(AiTaskAssistRequest request);

  Future<String> assistTaskDescription(AiTaskAssistRequest request);
}

class AiProviderNotConfigured implements AiProvider {
  const AiProviderNotConfigured();

  @override
  Stream<String> streamChat({
    required List<AiChatMessage> history,
    required String userPrompt,
  }) async* {
    throw StateError('AI provider is not configured.');
  }

  @override
  Future<String> sendChat({
    required List<AiChatMessage> history,
    required String userPrompt,
  }) async {
    throw StateError('AI provider is not configured.');
  }

  @override
  Future<String> assistTaskTitle(AiTaskAssistRequest request) async {
    throw StateError('AI provider is not configured.');
  }

  @override
  Future<String> assistTaskDescription(AiTaskAssistRequest request) async {
    throw StateError('AI provider is not configured.');
  }
}

class AiProviderRemoteStub implements AiProvider {
  const AiProviderRemoteStub();

  @override
  Stream<String> streamChat({
    required List<AiChatMessage> history,
    required String userPrompt,
  }) async* {
    throw UnimplementedError('Remote AI provider not implemented yet.');
  }

  @override
  Future<String> sendChat({
    required List<AiChatMessage> history,
    required String userPrompt,
  }) async {
    throw UnimplementedError('Remote AI provider not implemented yet.');
  }

  @override
  Future<String> assistTaskTitle(AiTaskAssistRequest request) async {
    throw UnimplementedError('Remote AI provider not implemented yet.');
  }

  @override
  Future<String> assistTaskDescription(AiTaskAssistRequest request) async {
    throw UnimplementedError('Remote AI provider not implemented yet.');
  }
}
