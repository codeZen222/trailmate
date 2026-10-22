import 'package:flutter/material.dart';

/// 消费分类。固定 8 类而非用户自建：分类是统计的骨架，
/// 自由添加会把同类支出切碎（"打车/交通/交通费"变三类），饼图就失去意义。
enum ExpenseCategory {
  transport('transport', '交通', '✈️', Color(0xFF4A7FB5)),
  stay('stay', '住宿', '🏨', Color(0xFF7B5EA7)),
  food('food', '餐饮', '🍜', Color(0xFFD98032)),
  ticket('ticket', '门票', '🎫', Color(0xFF3E9B7A)),
  shopping('shopping', '购物', '🛍️', Color(0xFFCC5A78)),
  fun('fun', '娱乐', '🎮', Color(0xFFE0A93C)),
  medical('medical', '医疗', '🏥', Color(0xFF5BA8A8)),
  other('other', '其他', '📦', Color(0xFF8A8A8A));

  const ExpenseCategory(this.key, this.label, this.emoji, this.color);

  final String key;
  final String label;
  final String emoji;
  final Color color;

  static const List<ExpenseCategory> all = values;

  static ExpenseCategory fromKey(String? k) {
    if (k == null || k.isEmpty) return ExpenseCategory.other;
    for (final c in values) {
      if (c.key == k) return c;
    }
    return ExpenseCategory.other;
  }
}

/// 金额工具：底层存「分」，界面按「元」交互。
class Money {
  Money._();

  /// 分 → 元（显示用）。
  static double yuan(int cents) => cents / 100.0;

  /// 元 → 分。四舍五入避免浮点截断（19.99 元必须正好等于 1999 分）。
  static int cents(double yuanValue) => (yuanValue * 100).round();

  /// 解析用户输入。失败返回 null。
  static int? parseInput(String raw) {
    final t = raw.trim().replaceAll(',', '').replaceAll('¥', '');
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    if (v == null || v < 0) return null;
    return cents(v);
  }

  /// 千分位显示，如 1,280.00。
  static String format(int centsValue, {bool withSymbol = true}) {
    final yuanValue = centsValue / 100.0;
    final fixed = yuanValue.toStringAsFixed(2);
    final dot = fixed.indexOf('.');
    final intPart = fixed.substring(0, dot);
    final sign = intPart.startsWith('-') ? '-' : '';
    final digits = sign.isEmpty ? intPart : intPart.substring(1);
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
      buf.write(digits[i]);
    }
    final body = '$sign$buf.${fixed.substring(dot + 1)}';
    return withSymbol ? '¥$body' : body;
  }
}

class Expense {
  const Expense({
    required this.id,
    required this.tripId,
    required this.category,
    required this.amountCents,
    required this.expenseDate,
    required this.createdAt,
    this.logId,
    this.note,
  });

  final int id;
  final int tripId;
  final int? logId;
  final ExpenseCategory category;
  final int amountCents;
  final String? note;
  final DateTime expenseDate;
  final DateTime createdAt;

  double get amountYuan => Money.yuan(amountCents);

  Expense copyWith({
    int? id,
    int? tripId,
    int? logId,
    ExpenseCategory? category,
    int? amountCents,
    String? note,
    DateTime? expenseDate,
    DateTime? createdAt,
  }) {
    return Expense(
      id: id ?? this.id,
      tripId: tripId ?? this.tripId,
      logId: logId ?? this.logId,
      category: category ?? this.category,
      amountCents: amountCents ?? this.amountCents,
      note: note ?? this.note,
      expenseDate: expenseDate ?? this.expenseDate,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'tripId': tripId,
        'logId': logId,
        'category': category.key,
        'amountCents': amountCents,
        'note': note,
        'expenseDate': expenseDate.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory Expense.fromJson(Map<String, dynamic> j) => Expense(
        id: j['id'] as int,
        tripId: j['tripId'] as int,
        logId: j['logId'] as int?,
        category: ExpenseCategory.fromKey(j['category'] as String?),
        amountCents: (j['amountCents'] as num?)?.toInt() ?? 0,
        note: j['note'] as String?,
        expenseDate: DateTime.parse(j['expenseDate'] as String),
        createdAt: DateTime.parse(
            (j['createdAt'] as String?) ?? (j['expenseDate'] as String)),
      );
}
