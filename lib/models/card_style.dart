import 'package:flutter/material.dart';

/// 档案卡（证件样式）的可选配色。
/// 每张卡有独立的标题带、底面渐变与墨色，供用户在编辑档案时自选。
enum CardStyle {
  green(
    key: 'green',
    label: '永居绿',
    emoji: '🟢',
    bandTop: Color(0xFF2F6B4E),
    bandBottom: Color(0xFF3D7C5B),
    bodyTop: Color(0xFFE3F2E9),
    bodyBottom: Color(0xFFC4E0CE),
    ink: Color(0xFF1C3A2B),
    inkSoft: Color(0xFF4A6B58),
  ),
  blue(
    key: 'blue',
    label: '护照蓝',
    emoji: '🔵',
    bandTop: Color(0xFF1F3A6B),
    bandBottom: Color(0xFF2C5296),
    bodyTop: Color(0xFFE8EFF9),
    bodyBottom: Color(0xFFC7D9F0),
    ink: Color(0xFF16294A),
    inkSoft: Color(0xFF4A6285),
  ),
  red(
    key: 'red',
    label: '登机红',
    emoji: '🔴',
    bandTop: Color(0xFF8A2B34),
    bandBottom: Color(0xFFA83A45),
    bodyTop: Color(0xFFFCEDEE),
    bodyBottom: Color(0xFFF3D3D6),
    ink: Color(0xFF4A161B),
    inkSoft: Color(0xFF8A5257),
  ),
  black(
    key: 'black',
    label: '头等黑金',
    emoji: '⚫️',
    bandTop: Color(0xFF23252B),
    bandBottom: Color(0xFF33363F),
    bodyTop: Color(0xFFF4F1EA),
    bodyBottom: Color(0xFFDED8CB),
    ink: Color(0xFF23252B),
    inkSoft: Color(0xFF6B6455),
  ),
  purple(
    key: 'purple',
    label: '夜航紫',
    emoji: '🟣',
    bandTop: Color(0xFF3B2C63),
    bandBottom: Color(0xFF4E3B82),
    bodyTop: Color(0xFFF0ECFA),
    bodyBottom: Color(0xFFD9CFF2),
    ink: Color(0xFF241A3E),
    inkSoft: Color(0xFF5E5480),
  );

  const CardStyle({
    required this.key,
    required this.label,
    required this.emoji,
    required this.bandTop,
    required this.bandBottom,
    required this.bodyTop,
    required this.bodyBottom,
    required this.ink,
    required this.inkSoft,
  });

  /// 存入 Profile.cardStyle 的稳定标识。
  final String key;
  final String label;
  final String emoji;

  /// 标题带渐变。
  final Color bandTop;
  final Color bandBottom;
  /// 卡面渐变。
  final Color bodyTop;
  final Color bodyBottom;
  /// 主文字色。
  final Color ink;
  /// 次要文字色。
  final Color inkSoft;

  static const CardStyle fallback = CardStyle.green;

  static CardStyle fromKey(String? k) {
    if (k == null || k.isEmpty) return fallback;
    for (final s in values) {
      if (s.key == k) return s;
    }
    return fallback;
  }

  /// 标题带上的文字色（深底配白字）。
  Color get onBand => Colors.white;
}
