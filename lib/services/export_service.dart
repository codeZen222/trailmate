import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../database/app_database.dart' as db;
import '../providers/database_provider.dart';
import '../utils/date_utils.dart' as date_utils;

/// 数据导出服务：JSON / Markdown / PDF。全部返回生成的文件路径。
class ExportService {
  final db.AppDatabase _db;
  ExportService(this._db);

  // ---------- 4.2 JSON 全库导出 ----------
  Future<String> exportJson() async {
    final trips = await _db.getAllTrips();
    final footprints = await _db.getAllFootprints();
    final tags = await _db.getAllTags();
    // 档案以 JSON 字符串存放，导出时还原成对象；无档案或损坏则为 null。
    final rawProfile = await _db.getSetting('user_profile');
    Object? profileJson;
    if (rawProfile != null && rawProfile.isNotEmpty) {
      try {
        profileJson = jsonDecode(rawProfile);
      } catch (_) {
        profileJson = rawProfile;
      }
    }

    final data = <String, dynamic>{
      'app': 'TrailMate',
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'trips': <dynamic>[],
      'footprints': footprints.map((f) => {
        'cityName': f.cityName,
        'country': f.country,
        'latitude': f.latitude,
        'longitude': f.longitude,
        'visitCount': f.visitCount,
        'firstVisitedAt': f.firstVisitedAt.toIso8601String(),
        'latestVisitedAt': f.latestVisitedAt.toIso8601String(),
      }).toList(),
      'tags': tags.map((t) => {'name': t.name, 'icon': t.icon}).toList(),
      // 消费记录（金额为「分」，避免浮点误差）
      'expenses': (await _db.getAllExpenses())
          .map((e) => {
                'tripId': e.tripId,
                'logId': e.logId,
                'category': e.category,
                'amountCents': e.amountCents,
                'amountYuan': e.amountCents / 100.0,
                'note': e.note,
                'expenseDate': e.expenseDate.toIso8601String(),
              })
          .toList(),
      // 个人旅行档案（存于 settings 表的 JSON）
      'profile': profileJson,
    };

    for (final trip in trips) {
      final logs = await _db.getLogsByTrip(trip.id);
      final tripTags = await _db.getTagsByTrip(trip.id);
      final logList = <dynamic>[];
      for (final log in logs) {
        final images = await _db.getImagesByLog(log.id);
        final loc = await _db.getLocationByLog(log.id);
        logList.add({
          'date': log.date.toIso8601String(),
          'title': log.title,
          'content': log.content,
          'weather': log.weather,
          'rating': log.rating,
          'images': images.map((i) => i.filePath).toList(),
          'location': loc == null ? null : {
            'latitude': loc.latitude,
            'longitude': loc.longitude,
            'cityName': loc.cityName,
            'placeName': loc.placeName,
          },
        });
      }
      (data['trips'] as List).add({
        'destination': trip.destination,
        'startDate': trip.startDate.toIso8601String(),
        'endDate': trip.endDate.toIso8601String(),
        'rating': trip.rating,
        'notes': trip.notes,
        'coverPath': trip.coverPath,
        'tags': tripTags.map((t) => t.name).toList(),
        'logs': logList,
      });
    }

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/trailmate_export_${_stamp()}.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    return file.path;
  }

  // ---------- 4.3 Markdown 单旅程导出 ----------
  Future<String> exportMarkdown(int tripId) async {
    final trip = await _db.getTripById(tripId);
    if (trip == null) throw Exception('旅程不存在');
    final logs = await _db.getLogsByTrip(tripId);
    final tags = await _db.getTagsByTrip(tripId);

    final sb = StringBuffer();
    sb.writeln('# ${trip.destination}');
    sb.writeln();
    sb.writeln('> ${date_utils.formatDateRange(trip.startDate, trip.endDate)} · '
        '${date_utils.formatDuration(trip.endDate.difference(trip.startDate).inDays + 1)}');
    sb.writeln();
    if (tags.isNotEmpty) {
      sb.writeln('标签：${tags.map((t) => '#${t.name}').join(' ')}');
      sb.writeln();
    }
    if (trip.notes != null && trip.notes!.isNotEmpty) {
      sb.writeln('${trip.notes}');
      sb.writeln();
    }
    sb.writeln('---');
    sb.writeln();

    for (final log in logs) {
      sb.writeln('## ${date_utils.formatDateChinese(log.date)}'
          '${log.weather != null ? ' · ${log.weather}' : ''}');
      sb.writeln();
      if (log.title != null && log.title!.isNotEmpty) {
        sb.writeln('### ${log.title}');
        sb.writeln();
      }
      sb.writeln(log.content);
      sb.writeln();
      final images = await _db.getImagesByLog(log.id);
      if (images.isNotEmpty) {
        for (final img in images) {
          sb.writeln('![photo](${img.filePath})');
        }
        sb.writeln();
      }
    }

    final dir = await getApplicationDocumentsDirectory();
    final safeName = trip.destination.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final file = File('${dir.path}/$safeName.md');
    await file.writeAsString(sb.toString());
    return file.path;
  }

  // ---------- 4.4 PDF 纪念册导出 ----------
  Future<String> exportPdf(int tripId) async {
    final trip = await _db.getTripById(tripId);
    if (trip == null) throw Exception('旅程不存在');
    final logs = await _db.getLogsByTrip(tripId);

    final doc = pw.Document();

    // 封面页
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (context) => pw.Center(
        child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            pw.Text(trip.destination,
                style: pw.TextStyle(fontSize: 36, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 16),
            pw.Text(date_utils.formatDateRange(trip.startDate, trip.endDate),
                style: const pw.TextStyle(fontSize: 16)),
            pw.SizedBox(height: 8),
            pw.Text(
                '${trip.endDate.difference(trip.startDate).inDays + 1} 天旅程',
                style: const pw.TextStyle(fontSize: 14)),
            pw.SizedBox(height: 48),
            pw.Text('TrailMate 旅行纪念册',
                style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey600)),
          ],
        ),
      ),
    ));

    // 正文页（按日志分段）
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (context) {
        final blocks = <pw.Widget>[];
        for (final log in logs) {
          blocks.add(pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 8),
            child: pw.Text(
              '${date_utils.formatDateChinese(log.date)}'
              '${log.weather != null ? '  ·  ${log.weather}' : ''}',
              style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
            ),
          ));
          if (log.title != null && log.title!.isNotEmpty) {
            blocks.add(pw.Text(log.title!,
                style: const pw.TextStyle(fontSize: 13)));
            blocks.add(pw.SizedBox(height: 4));
          }
          blocks.add(pw.Text(_stripMd(log.content),
              style: const pw.TextStyle(fontSize: 11)));
          blocks.add(pw.SizedBox(height: 16));
        }
        if (logs.isEmpty) {
          blocks.add(pw.Text('这篇旅程还没有日志。',
              style: const pw.TextStyle(fontSize: 12)));
        }
        return blocks;
      },
    ));

    final dir = await getApplicationDocumentsDirectory();
    final safeName = trip.destination.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final file = File('${dir.path}/$safeName.pdf');
    await file.writeAsBytes(await doc.save());
    return file.path;
  }

  /// 粗略去掉 Markdown 标记，便于 PDF 纯文本呈现。
  static String _stripMd(String s) => s
      .replaceAllMapped(RegExp(r'^#{1,6}\s+', multiLine: true), (_) => '')
      .replaceAll(RegExp(r'\*\*(.+?)\*\*'), r'$1')
      .replaceAll(RegExp(r'(?<!\*)\*(?!\*)(.+?)\*'), r'$1')
      .replaceAll(RegExp(r'^[-*]\s+', multiLine: true), '• ')
      .replaceAll(RegExp(r'^>\s?', multiLine: true), '');

  static String _stamp() {
    final n = DateTime.now();
    return '${n.year}${n.month.toString().padLeft(2, '0')}${n.day.toString().padLeft(2, '0')}';
  }
}

final exportServiceProvider =
    Provider<ExportService>((ref) => ExportService(ref.watch(databaseProvider)));
