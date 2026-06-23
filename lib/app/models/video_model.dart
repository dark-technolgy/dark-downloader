class VideoModel {
  final String id;
  final String url;
  final String title;
  final String? description;
  final String? thumbnailUrl;
  final String platform;
  final String quality;
  final double? fileSize;
  final int? duration;
  final DateTime createdAt;
  final DateTime? downloadedAt;
  final String? downloadPath;
  final String status;

  const VideoModel({
    required this.id,
    required this.url,
    required this.title,
    this.description,
    this.thumbnailUrl,
    required this.platform,
    required this.quality,
    this.fileSize,
    this.duration,
    required this.createdAt,
    this.downloadedAt,
    this.downloadPath,
    this.status = 'pending',
  });

  VideoModel copyWith({
    String? id,
    String? url,
    String? title,
    String? description,
    String? thumbnailUrl,
    String? platform,
    String? quality,
    double? fileSize,
    int? duration,
    DateTime? createdAt,
    DateTime? downloadedAt,
    String? downloadPath,
    String? status,
  }) {
    return VideoModel(
      id: id ?? this.id,
      url: url ?? this.url,
      title: title ?? this.title,
      description: description ?? this.description,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      platform: platform ?? this.platform,
      quality: quality ?? this.quality,
      fileSize: fileSize ?? this.fileSize,
      duration: duration ?? this.duration,
      createdAt: createdAt ?? this.createdAt,
      downloadedAt: downloadedAt ?? this.downloadedAt,
      downloadPath: downloadPath ?? this.downloadPath,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'url': url,
    'title': title,
    'description': description,
    'thumbnail_url': thumbnailUrl,
    'platform': platform,
    'quality': quality,
    'file_size': fileSize,
    'duration': duration,
    'created_at': createdAt.toIso8601String(),
    'downloaded_at': downloadedAt?.toIso8601String(),
    'download_path': downloadPath,
    'status': status,
  };

  factory VideoModel.fromJson(Map<String, dynamic> json) => VideoModel(
    id: json['id'] as String,
    url: json['url'] as String,
    title: json['title'] as String,
    description: json['description'] as String?,
    thumbnailUrl: json['thumbnail_url'] as String?,
    platform: json['platform'] as String,
    quality: json['quality'] as String,
    fileSize: (json['file_size'] as num?)?.toDouble(),
    duration: json['duration'] as int?,
    createdAt: DateTime.parse(json['created_at'] as String),
    downloadedAt: json['downloaded_at'] != null
        ? DateTime.parse(json['downloaded_at'] as String)
        : null,
    downloadPath: json['download_path'] as String?,
    status: json['status'] as String? ?? 'pending',
  );
}
