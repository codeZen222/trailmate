import '../models/mood_type.dart';

/// copyWith 的「未传参」哨兵，用于区分"保持原值"和"显式置空"。
const Object _unset = Object();

class Log {
  final int id;
  final int tripId;
  final DateTime date;
  final String? title;
  final String content;
  final String? weather;
  /// 心情标签原始值（存 MoodType.key）。旧数据可能为 null。
  final String? moodTag;
  final int? rating;
  final DateTime createdAt;
  final DateTime updatedAt;

  Log({
    required this.id,
    required this.tripId,
    required this.date,
    this.title,
    required this.content,
    this.weather,
    this.moodTag,
    this.rating,
    required this.createdAt,
    required this.updatedAt,
  });

  /// 解析后的心情；无法识别或为空时返回 null。
  MoodType? get mood => MoodType.fromKey(moodTag);

  String get summary => content.length > 100
      ? '${content.substring(0, 100)}...'
      : content;

  Log copyWith({
    int? id,
    int? tripId,
    DateTime? date,
    String? title,
    String? content,
    String? weather,
    Object? moodTag = _unset,
    int? rating,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Log(
      id: id ?? this.id,
      tripId: tripId ?? this.tripId,
      date: date ?? this.date,
      title: title ?? this.title,
      content: content ?? this.content,
      weather: weather ?? this.weather,
      moodTag: identical(moodTag, _unset) ? this.moodTag : moodTag as String?,
      rating: rating ?? this.rating,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'tripId': tripId,
    'date': date.toIso8601String(),
    'title': title,
    'content': content,
    'weather': weather,
    'moodTag': moodTag,
    'rating': rating,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Log.fromJson(Map<String, dynamic> json) => Log(
    id: json['id'] as int,
    tripId: json['tripId'] as int,
    date: DateTime.parse(json['date'] as String),
    title: json['title'] as String?,
    content: json['content'] as String,
    weather: json['weather'] as String?,
    moodTag: json['moodTag'] as String?,
    rating: json['rating'] as int?,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );
}
