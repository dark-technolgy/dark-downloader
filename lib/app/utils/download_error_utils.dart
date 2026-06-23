/// Maps Rust/network errors to localized keys and retry policy.
String downloadErrorL10nKey(String raw) {
  final lower = raw.toLowerCase();
  if (lower.contains('cancel')) return 'dm_err_cancelled';
  if (lower.contains('socket') ||
      lower.contains('connection reset') ||
      lower.contains('connection refused') ||
      lower.contains('broken pipe') ||
      lower.contains('network is unreachable') ||
      lower.contains('failed host lookup') ||
      lower.contains('connection closed') ||
      lower.contains('connection lost')) {
    return 'dm_err_connection_lost';
  }
  if (lower.contains('timed out') || lower.contains('timeout')) {
    return 'dm_err_timeout';
  }
  if (lower.contains('no network') || lower.contains('offline')) {
    return 'dm_err_no_network';
  }
  if (lower.contains('403') || lower.contains('forbidden')) {
    return 'dm_err_http_forbidden';
  }
  if (lower.contains('404') || lower.contains('not found')) {
    return 'dm_err_http_not_found';
  }
  if (lower.contains('expired') || lower.contains('403') || lower.contains('signature')) {
    return 'dm_err_link_expired';
  }
  if (lower.contains('no space') || lower.contains('enospc')) {
    return 'dm_err_no_space';
  }
  if (lower.contains('permission')) return 'dm_err_storage_permission';
  if (lower.contains('empty')) return 'dm_err_empty_file';
  return 'dm_fallback_failed';
}

bool isRetryableDownloadError(String? raw) {
  if (raw == null || raw.isEmpty) return true;
  final lower = raw.toLowerCase();
  if (lower.contains('cancel') && !lower.contains('connection')) return false;
  if (lower.contains('permission') || lower.contains('no space')) return false;
  if (lower.contains('forbidden') && lower.contains('expired')) return false;
  if (lower.contains('link_expired') || lower.contains('signature')) return false;
  return lower.contains('network') ||
      lower.contains('timeout') ||
      lower.contains('timed out') ||
      lower.contains('connection') ||
      lower.contains('socket') ||
      lower.contains('reset') ||
      lower.contains('offline') ||
      lower.contains('empty file') ||
      lower.contains('http') ||
      lower.contains('failed');
}
