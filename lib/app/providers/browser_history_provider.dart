import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class BrowserHistoryItem {
  final String id;
  final String title;
  final String url;
  final DateTime visitedAt;

  BrowserHistoryItem({
    required this.id,
    required this.title,
    required this.url,
    required this.visitedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'url': url,
      'visitedAt': visitedAt.toIso8601String(),
    };
  }

  factory BrowserHistoryItem.fromJson(Map<String, dynamic> json) {
    return BrowserHistoryItem(
      id: json['id'] as String,
      title: json['title'] as String,
      url: json['url'] as String,
      visitedAt: DateTime.parse(json['visitedAt'] as String),
    );
  }
}

class BrowserHistoryNotifier extends Notifier<List<BrowserHistoryItem>> {
  static const _prefsKey = 'browser_history';
  final _uuid = const Uuid();

  @override
  List<BrowserHistoryItem> build() {
    _loadHistory();
    return [];
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getStringList(_prefsKey);
    if (historyJson != null) {
      final items = historyJson
          .map((item) => BrowserHistoryItem.fromJson(jsonDecode(item)))
          .toList();
      // Sort by newest first
      items.sort((a, b) => b.visitedAt.compareTo(a.visitedAt));
      state = items;
    }
  }

  Future<void> _saveHistory(List<BrowserHistoryItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = items.map((item) => jsonEncode(item.toJson())).toList();
    await prefs.setStringList(_prefsKey, historyJson);
  }

  void addVisit(String url, String title) {
    if (url.isEmpty || url == 'about:blank' || !url.startsWith('http')) return;
    
    // Avoid immediate duplicates
    if (state.isNotEmpty && state.first.url == url) {
      return; 
    }

    final newItem = BrowserHistoryItem(
      id: _uuid.v4(),
      title: title.isEmpty ? url : title,
      url: url,
      visitedAt: DateTime.now(),
    );

    // Keep history manageable (e.g., max 500 items)
    final updatedList = [newItem, ...state];
    if (updatedList.length > 500) {
      updatedList.removeRange(500, updatedList.length);
    }

    state = updatedList;
    _saveHistory(updatedList);
  }

  void removeVisit(String id) {
    final updatedList = state.where((item) => item.id != id).toList();
    state = updatedList;
    _saveHistory(updatedList);
  }

  void clearHistory() {
    state = [];
    _saveHistory([]);
  }
}

final browserHistoryProvider = NotifierProvider<BrowserHistoryNotifier, List<BrowserHistoryItem>>(
  BrowserHistoryNotifier.new,
);
