import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/supabase_config.dart';
import 'auth_provider.dart';

class HistoryItem {
  final String id;
  final String title;
  final String url;
  final String platform;
  final String status;
  final String kind;
  final DateTime createdAt;

  HistoryItem({
    required this.id,
    required this.title,
    required this.url,
    required this.platform,
    required this.status,
    required this.kind,
    required this.createdAt,
  });

  factory HistoryItem.fromJson(Map<String, dynamic> json) {
    return HistoryItem(
      id: json['id'],
      title: json['video_title'] ?? json['title'] ?? 'Unknown',
      url: json['video_url'] ?? json['url'] ?? '',
      platform: json['platform'] ?? 'Unknown',
      status: json['status'] ?? 'completed',
      kind: json['kind'] ?? 'http',
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class HistoryNotifier extends Notifier<AsyncValue<List<HistoryItem>>> {
  @override
  AsyncValue<List<HistoryItem>> build() {
    _load();
    return const AsyncValue.loading();
  }

  Future<void> _load() async {
    final user = ref.read(authProvider).user;
    if (user == null) {
      state = const AsyncValue.data([]);
      return;
    }

    try {
      final data = await supabase
          .from('download_history')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false);
      
      final items = (data as List).map((e) => HistoryItem.fromJson(e)).toList();
      state = AsyncValue.data(items);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> addItem({
    required String title,
    required String url,
    String platform = 'Unknown',
    String kind = 'http',
    String status = 'completed',
  }) async {
    final user = ref.read(authProvider).user;
    if (user == null) return;

    try {
      await supabase.from('download_history').insert({
        'user_id': user.id,
        'video_title': title,
        'video_url': url,
        'platform': platform,
        'kind': kind,
        'status': status,
      });
      await _load();
    } catch (e) {
      // Error logging
    }
  }

  Future<void> deleteItem(String itemId) async {
    final user = ref.read(authProvider).user;
    if (user == null) return;

    try {
      await supabase.from('download_history').delete().eq('id', itemId);
      await _load();
    } catch (e) {
      // Error logging
    }
  }

  Future<void> clearHistory() async {
    final user = ref.read(authProvider).user;
    if (user == null) return;

    try {
      await supabase.from('download_history').delete().eq('user_id', user.id);
      state = const AsyncValue.data([]);
    } catch (e) {
      // Error logging
    }
  }
}

final historyProvider = NotifierProvider<HistoryNotifier, AsyncValue<List<HistoryItem>>>(HistoryNotifier.new);
