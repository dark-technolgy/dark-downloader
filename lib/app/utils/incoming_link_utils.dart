/// Normalizes text or [Uri] from shares / app links into a single download target.
String? extractFirstDownloadTarget(String input) {
  final t = input.trim();
  if (t.isEmpty) return null;
  if (t.startsWith('magnet:?')) return t;

  final direct = Uri.tryParse(t);
  if (direct != null &&
      (direct.scheme == 'http' || direct.scheme == 'https') &&
      direct.host.isNotEmpty) {
    return t;
  }

  final re = RegExp(
    r'(https?://[^\s<>"{}|\\^`\[\]]+|magnet:\?[^\s<>"{}|\\^`\[\]]+)',
    caseSensitive: false,
  );
  final m = re.firstMatch(t);
  if (m == null) return null;
  var s = m.group(1)!;
  s = s.replaceAll(RegExp(r'[.,;:!?)]+$'), '');
  return s.isEmpty ? null : s;
}

/// Maps an app/deep link [Uri] to a payload string for the downloader.
String? uriToDownloadPayload(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'darkdownloader' || scheme == 'com.darkdownloader') {
    final q =
        uri.queryParameters['url'] ??
        uri.queryParameters['link'] ??
        uri.queryParameters['target'] ??
        uri.queryParameters['q'];
    if (q != null && q.isNotEmpty) {
      return extractFirstDownloadTarget(Uri.decodeComponent(q));
    }
    if (uri.path.isNotEmpty && uri.path != '/') {
      final p = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
      return extractFirstDownloadTarget(Uri.decodeComponent(p));
    }
    return null;
  }
  if (scheme == 'magnet') {
    return uri.toString();
  }
  if (scheme == 'http' || scheme == 'https') {
    return uri.toString();
  }
  return null;
}
