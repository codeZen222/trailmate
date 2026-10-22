import 'package:intl/intl.dart';

String formatDate(DateTime date) {
  return DateFormat('yyyy/MM/dd').format(date);
}

String formatDateChinese(DateTime date) {
  return '${date.year}年${date.month}月${date.day}日';
}

String formatDateRange(DateTime start, DateTime end) {
  return '${formatDate(start)} - ${formatDate(end)}';
}

String formatShortDate(DateTime date) {
  return DateFormat('MM/dd').format(date);
}

String dayOfWeek(DateTime date) {
  final weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  return weekdays[date.weekday - 1];
}

int daysBetween(DateTime start, DateTime end) {
  return end.difference(start).inDays + 1;
}

String formatDuration(int days) {
  if (days == 1) return '1 天';
  return '$days 天';
}

bool isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

String getYearMonth(DateTime date) {
  return DateFormat('yyyy年MM月').format(date);
}