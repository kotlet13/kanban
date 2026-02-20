import 'ai_models.dart';
import 'ai_provider.dart';

class AiFacade {
  const AiFacade(this._provider);

  final AiProvider _provider;

  Stream<String> streamChat({
    required List<AiChatMessage> history,
    required String userPrompt,
  }) {
    return _provider.streamChat(history: history, userPrompt: userPrompt);
  }

  Future<String> sendChat({
    required List<AiChatMessage> history,
    required String userPrompt,
  }) {
    return _provider.sendChat(history: history, userPrompt: userPrompt);
  }

  Future<String> assistTaskTitle(AiTaskAssistRequest request) {
    return _provider.assistTaskTitle(request);
  }

  Future<String> assistTaskDescription(AiTaskAssistRequest request) {
    return _provider.assistTaskDescription(request);
  }
}
