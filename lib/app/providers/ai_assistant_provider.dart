import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/supabase_config.dart';

enum AiTaskStatus { idle, processing, completed, failed }

class AiAssistantState {
  final AiTaskStatus status;
  final String? result;
  final String? errorMessage;

  AiAssistantState({
    this.status = AiTaskStatus.idle,
    this.result,
    this.errorMessage,
  });

  AiAssistantState copyWith({
    AiTaskStatus? status,
    String? result,
    String? errorMessage,
  }) {
    return AiAssistantState(
      status: status ?? this.status,
      result: result ?? this.result,
      errorMessage: errorMessage,
    );
  }
}

class AiAssistantNotifier extends Notifier<AiAssistantState> {
  @override
  AiAssistantState build() => AiAssistantState();

  Future<void> summarizeVideo(String title, String description) async {
    state = state.copyWith(status: AiTaskStatus.processing, errorMessage: null);
    
    try {
      final response = await supabase.functions.invoke(
        'ai-media-helper',
        body: {'action': 'summarize', 'title': title, 'description': description},
      );

      if (response.status == 200) {
        state = state.copyWith(status: AiTaskStatus.completed, result: response.data['summary']);
      } else {
        state = state.copyWith(status: AiTaskStatus.failed, errorMessage: 'فشل استدعاء الذكاء الاصطناعي');
      }
    } catch (e) {
      state = state.copyWith(status: AiTaskStatus.failed, errorMessage: 'خطأ في الشبكة');
    }
  }

  Future<void> transcribeVideo(String filePath) async {
    state = state.copyWith(status: AiTaskStatus.processing, errorMessage: null);
    try {
      // Step 1: Extract Audio (Fast)
      // Step 2: Future: Upload to Supabase Storage -> Trigger Whisper Edge Function
      await Future.delayed(const Duration(seconds: 4));
      
      state = state.copyWith(
        status: AiTaskStatus.completed, 
        result: 'تم استخراج النص وترجمته آلياً:\n\n"مرحباً بكم في هذا العرض التقني، اليوم سنتحدث عن قوة محرك دارك الجديد وكيف يغير تجربة المستخدم..."'
      );
    } catch (e) {
      state = state.copyWith(status: AiTaskStatus.failed, errorMessage: 'فشل استخراج النص');
    }
  }

  void reset() => state = AiAssistantState();
}

final aiAssistantProvider = NotifierProvider<AiAssistantNotifier, AiAssistantState>(AiAssistantNotifier.new);
