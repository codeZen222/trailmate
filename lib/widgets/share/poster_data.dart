import 'package:flutter/material.dart';
import '../../models/expense_model.dart';
import '../../models/mood_type.dart';

/// 海报模板。每种模板构图差异明显，不是简单换色。
enum PosterTemplate {
  wave('wave', '撕纸海报', '🏔️'),
  editorial('editorial', '极简杂志', '📰'),
  polaroid('polaroid', '拍立得', '📸'),
  boarding('boarding', '登机牌', '🎫'),
  film('film', '胶片条', '🎞️');

  const PosterTemplate(this.key, this.label, this.emoji);

  /// 持久化用的稳定标识。
  final String key;
  final String label;
  final String emoji;

  static const PosterTemplate fallback = PosterTemplate.wave;

  static PosterTemplate fromKey(String? k) {
    if (k == null || k.isEmpty) return fallback;
    for (final t in values) {
      if (t.key == k) return t;
    }
    return fallback;
  }
}

/// 海报所需的全部数据，由分享页聚合后传入（模板自身不查库，
/// 保证预览与实际截图共用同一份实现）。
class TripPosterData {
  const TripPosterData({
    required this.destination,
    required this.startDate,
    required this.endDate,
    required this.days,
    required this.photoPaths,
    this.cities = const [],
    this.tagNames = const [],
    this.logCount = 0,
    this.photoCount = 0,
    this.caption,
    this.notes,
    this.rating,
    this.mood,
    this.totalCents = 0,
  });

  final String destination;
  final DateTime startDate;
  final DateTime endDate;
  final int days;

  /// 第一张为主图（旅程封面优先），其余作补充图条。
  final List<String> photoPaths;
  final List<String> cities;
  final List<String> tagNames;
  final int logCount;
  final int photoCount;

  /// 用户可编辑的一句文案。
  final String? caption;
  final String? notes;
  final int? rating;
  final MoodType? mood;

  /// 本旅程消费总额（分）；0 表示未记账，海报上不显示该行。
  final int totalCents;

  /// 海报上的花费文案；无记账时返回 null。
  String? get costLine {
    if (totalCents <= 0) return null;
    final perDay = (totalCents / (days <= 0 ? 1 : days)).round();
    return '总花费 ${Money.format(totalCents)} · 日均 ${Money.format(perDay)}';
  }

  String? get mainPhoto => photoPaths.isEmpty ? null : photoPaths.first;

  /// 主图之外的若干张，用于缩略图条。
  List<String> extraPhotos({int max = 3}) {
    if (photoPaths.length <= 1) return const [];
    final rest = photoPaths.sublist(1);
    return rest.length > max ? rest.sublist(rest.length - max) : rest;
  }

  /// 顶部文案；留空时给一个不尴尬的默认。
  String get displayCaption {
    final c = (caption ?? '').trim();
    return c.isEmpty ? '用 脚 步 丈 量 世 界' : c;
  }

  String get dateRange => '${_fmt(startDate)} — ${_fmt(endDate)}';

  static String _fmt(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

  /// notes 摘录成一行。
  String get notesExcerpt {
    final n = (notes ?? '').trim();
    if (n.isEmpty) return '';
    final one = n.replaceAll(RegExp(r'\s+'), ' ');
    return one.length <= 60 ? one : '${one.substring(0, 60)}…';
  }

  /// 无照片时的统一渐变兜底。
  static const fallbackColors = [Color(0xFF3E6B5A), Color(0xFF8FB9A8)];
}
