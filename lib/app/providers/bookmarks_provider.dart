import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/supabase_config.dart';
import 'auth_provider.dart';

class BookmarkItem {
  final String id;
  final String title;
  final String url;
  final String category;
  final DateTime createdAt;

  BookmarkItem({
    required this.id,
    required this.title,
    required this.url,
    required this.category,
    required this.createdAt,
  });

  factory BookmarkItem.fromJson(Map<String, dynamic> json) {
    return BookmarkItem(
      id: json['id'],
      title: json['title'] ?? 'بدون عنوان',
      url: json['url'] ?? '',
      category: json['category'] ?? 'General',
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class BookmarksNotifier extends Notifier<AsyncValue<List<BookmarkItem>>> {
  @override
  AsyncValue<List<BookmarkItem>> build() {
    // Re-load bookmarks when auth state changes
    ref.listen(authProvider, (previous, next) {
      if (previous?.user?.id != next.user?.id) {
        _load();
      }
    });
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
      state = const AsyncValue.loading();
      final data = await supabase
          .from('bookmarks')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false);
      
      final items = (data as List).map((e) => BookmarkItem.fromJson(e)).toList();
      state = AsyncValue.data(items);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() => _load();

  Future<void> addBookmark(String title, String url, {String category = 'General'}) async {
    final user = ref.read(authProvider).user;
    if (user == null) return;

    try {
      await supabase.from('bookmarks').upsert({
        'user_id': user.id,
        'title': title,
        'url': url,
        'category': category,
      }, onConflict: 'user_id, url',);
      _load();
    } catch (e) {
      // Error logging
    }
  }

  Future<void> removeBookmark(String bookmarkId) async {
    try {
      await supabase.from('bookmarks').delete().eq('id', bookmarkId);
      _load();
    } catch (e) {
      // Error logging
    }
  }

  bool isBookmarked(String url) {
    return state.maybeWhen(
      data: (items) => items.any((i) => i.url == url),
      orElse: () => false,
    );
  }
}

final bookmarksProvider = NotifierProvider<BookmarksNotifier, AsyncValue<List<BookmarkItem>>>(BookmarksNotifier.new);
