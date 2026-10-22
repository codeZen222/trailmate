import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../database/app_database.dart' as db;

/// 匿名使用统计（心跳）。
///
/// 【设计边界 —— 只传这些】
///   { day: "2026-10-13", installId: "<随机 UUID>", app: "trailmate", version: "1.0.0+1" }
/// 不含日记内容、照片、地名、坐标、手机号，也不读 IMEI / AndroidID / OAID。
/// installId 是本机随机生成的 UUID，卸载重装即更换 —— 因此无法反向识别到人，
/// 这正是刻意选择的取舍：够算 DAU/留存，不够监控个人。
///
/// 【绝不影响使用】所有失败都静默吞掉：无网络、域名没配、服务端挂了，
/// 都只是这次没记上而已，不重试轰炸、不弹提示、不阻塞任何界面。
class AnalyticsService {
  AnalyticsService(this._db);

  final db.AppDatabase _db;

  /// Workers 部署地址。留空则整个统计自动停用（不发请求、不报错）。
  static const String endpoint =
      'https://trailmate-ping.3222978058.workers.dev/ping';

  static const String _keyInstallId = 'analytics_install_id';
  static const String _keyLastDay = 'analytics_last_day';

  bool get enabled => endpoint.isNotEmpty;

  /// 本机安装标识；首次调用时生成并持久化。
  Future<String> _installId() async {
    final saved = await _db.getSetting(_keyInstallId);
    if (saved != null && saved.isNotEmpty) return saved;
    final id = _randomId();
    await _db.setSetting(_keyInstallId, id);
    return id;
  }

  static String _randomId() {
    // 不用 uuid 包，避免为一个统计功能再加依赖
    final r = Random.secure();
    String seg(int n) =>
        List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
    return '${seg(8)}${seg(4)}${seg(4)}${seg(12)}';
  }

  /// 每天最多上报一次。同一天重复启动直接跳过。
  Future<void> pingToday() async {
    if (!enabled) return;
    try {
      final now = DateTime.now();
      final today =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      final last = await _db.getSetting(_keyLastDay);
      if (last == today) return; // 今天已经打过

      final id = await _installId();
      await Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 6),
        receiveTimeout: const Duration(seconds: 6),
        sendTimeout: const Duration(seconds: 6),
      ))
          .post(endpoint, data: {
        'day': today,
        'installId': id,
        'app': 'trailmate',
        'version': kDebugMode ? 'debug' : '1.0.0+1',
      });

      // 只有成功才记录"今天已上报"，失败则下次启动再试
      await _db.setSetting(_keyLastDay, today);
    } catch (e) {
      debugPrint('analytics ping 跳过: $e');
    }
  }
}
