// 纯逻辑测试：复刻 trip_create_page.dart 里 _pickDate 的日期约束算法，
// 验证「结束日期不得早于开始日期、可以等于」这条规则。
// 不依赖 Flutter widget，直接跑 dart test 即可。
import 'package:flutter_test/flutter_test.dart';

DateTime? dayOf(DateTime? d) =>
    d == null ? null : DateTime(d.year, d.month, d.day);

/// 返回本次选择后 (start, end)，null 表示被拒绝写入。
({DateTime start, DateTime? end})? applyPick({
  required DateTime? startDate,
  required DateTime? endDate,
  required bool isStart,
  required DateTime picked,
}) {
  final startDay = dayOf(startDate);
  final endDay = dayOf(endDate);
  final firstDate = isStart ? DateTime(2000) : (startDay ?? DateTime(2000));
  // 选择器不会给出 firstDate 之前的日期，这里模拟日历仍递回一个值。
  if (picked.isBefore(firstDate)) return null;
  final day = dayOf(picked)!;
  if (!isStart && startDay != null && day.isBefore(startDay)) return null;
  if (isStart) {
    return (
      start: day,
      end: (endDay != null && endDay.isBefore(day)) ? day : endDay,
    );
  }
  return (start: startDay ?? day, end: day);
}

/// 保存前的兜底校验：返回 null 表示放行，否则为错误提示。
String? validateSave({required DateTime? start, required DateTime? end}) {
  if (start == null) return '请选择开始日期';
  final e = end ?? start; // 未填归期时 endDate 等同出发日
  if (e.isBefore(start)) return '结束日期不能早于开始日期';
  return null;
}

void main() {
  group('结束日期 >= 开始日期', () {
    test('结束日期早于开始日期被拒绝', () {
      expect(
        applyPick(
          startDate: DateTime(2026, 10, 10),
          endDate: null,
          isStart: false,
          picked: DateTime(2026, 10, 5),
        ),
        isNull,
      );
    });

    test('结束日期等于开始日期允许（一日行程）', () {
      final r = applyPick(
        startDate: DateTime(2026, 10, 10),
        endDate: null,
        isStart: false,
        picked: DateTime(2026, 10, 10),
      );
      expect(r!.end, DateTime(2026, 10, 10));
    });

    test('结束日期晚于开始日期允许', () {
      final r = applyPick(
        startDate: DateTime(2026, 10, 10),
        endDate: null,
        isStart: false,
        picked: DateTime(2026, 10, 20),
      );
      expect(r!.end, DateTime(2026, 10, 20));
    });

    test('带时分秒的同一天不算早于开始日期', () {
      final r = applyPick(
        startDate: DateTime(2026, 10, 10, 18, 30),
        endDate: null,
        isStart: false,
        picked: DateTime(2026, 10, 10, 9, 0),
      );
      expect(r!.end, DateTime(2026, 10, 10));
    });

    test('firstDate 之前（未选开始日期时为 2000-01-01）不可选', () {
      expect(
        applyPick(
          startDate: DateTime(2026, 10, 10),
          endDate: null,
          isStart: false,
          picked: DateTime(1999, 1, 1),
        ),
        isNull,
      );
    });

    test('把开始日期推到结束日期之后时，结束日期顶到开始日期', () {
      final r = applyPick(
        startDate: DateTime(2026, 10, 1),
        endDate: DateTime(2026, 10, 10),
        isStart: true,
        picked: DateTime(2026, 10, 15),
      );
      expect(r!.start, DateTime(2026, 10, 15));
      expect(r.end, DateTime(2026, 10, 15));
    });

    test('改早开始日期不影响已合法的结束日期', () {
      final r = applyPick(
        startDate: DateTime(2026, 10, 10),
        endDate: DateTime(2026, 10, 12),
        isStart: true,
        picked: DateTime(2026, 10, 5),
      );
      expect(r!.start, DateTime(2026, 10, 5));
      expect(r.end, DateTime(2026, 10, 12));
    });

    test('未选开始日期时结束日期可选任意日期', () {
      final r = applyPick(
        startDate: null,
        endDate: null,
        isStart: false,
        picked: DateTime(2026, 3, 3),
      );
      expect(r!.end, DateTime(2026, 3, 3));
    });
  });

  group('保存兜底校验', () {
    test('未选开始日期被拦截', () {
      expect(validateSave(start: null, end: null), '请选择开始日期');
    });

    test('没填归期（end==start）放行', () {
      expect(
          validateSave(start: DateTime(2026, 10, 10), end: null), isNull);
    });

    test('非法区间即使没经过选择器也会被拦截', () {
      expect(
        validateSave(
            start: DateTime(2026, 10, 10), end: DateTime(2026, 10, 5)),
        '结束日期不能早于开始日期',
      );
    });
  });

  test('不变式：任何一次操作后都不会出现 end < start', () {
    final dates = [
      DateTime(2026, 10, 1),
      DateTime(2026, 10, 10),
      DateTime(2026, 10, 20),
      DateTime(2027, 1, 1),
    ];
    for (final s in dates) {
      for (final e in dates) {
        for (final p in dates) {
          var st = s;
          DateTime? en = e;
          for (final isStart in [true, false]) {
            final r = applyPick(
                startDate: st, endDate: en, isStart: isStart, picked: p);
            if (r != null) {
              st = r.start;
              en = r.end;
            }
            expect(en == null || !en.isBefore(st), isTrue,
                reason: 'start=$st end=$en after pick=$p isStart=$isStart');
          }
        }
      }
    }
  });
}
