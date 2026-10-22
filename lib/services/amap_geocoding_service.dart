import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/app_database.dart' as db;
import '../providers/database_provider.dart';
import '../core/constants/secrets.dart';

/// 高德 Web 服务 Key（与 Android SDK Key 是不同类型，不能混用）。
/// 真实值在 secrets.dart —— 已被 .gitignore 排除，不进版本库。
const String amapWebKey = amapWebKeySecret;

/// 地理编码结果。
class GeoPoint {
  const GeoPoint({required this.latitude, required this.longitude, required this.formatted});

  final double latitude;
  final double longitude;
  final String formatted;
}

/// 高德 Web 服务地理编码。
///
/// 【为什么需要它】离线词表只覆盖约 300 个地名，县级/景区会漏，
/// 漏掉的城市坐标被写成 (0,0) 从而永远上不了地图。
/// Web 服务能把任意地名转成精确经纬度，且只是查坐标、不参与渲染，
/// 所以可以与自绘/高德底图共存。
///
/// 【限速是硬要求】实测该 Key 免费档 QPS 很低，连续请求会返回
/// `CUQPS_HAS_EXCEEDED_THE_LIMIT`。因此这里强制串行 + 节流，
/// 并把成功结果写进数据库缓存，避免同一地名反复请求。
class AmapGeocodingService {
  AmapGeocodingService(this._db) : _dio = Dio(BaseOptions(
          baseUrl: 'https://restapi.amap.com',
          connectTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 12),
        ));

  final db.AppDatabase _db;
  final Dio _dio;

  static const String _cachePrefix = 'geo_';

  /// 两次请求之间的最小间隔。低于此值极易触发限流。
  static const Duration _minInterval = Duration(milliseconds: 420);

  DateTime? _lastCall;
  Future<GeoPoint?>? _inFlight;
  String? _inFlightKey;

  /// 内存级短期结果缓存，避免同一次批量回填里重复查同名。
  final Map<String, GeoPoint?> _mem = {};

  /// 查询地名坐标。命中缓存优先；失败返回 null（调用方自行决定跳过或提示）。
  Future<GeoPoint?> locate(String address) async {
    final key = address.trim();
    if (key.isEmpty) return null;

    if (_mem.containsKey(key)) return _mem[key];

    final cached = await _readCache(key);
    if (cached != null) {
      _mem[key] = cached;
      return cached;
    }

    // 合并同一时刻对同一地址的并发请求
    if (_inFlight != null && _inFlightKey == key) return _inFlight;

    final task = _request(key);
    _inFlight = task;
    _inFlightKey = key;
    try {
      final r = await task;
      _mem[key] = r;
      return r;
    } finally {
      if (identical(_inFlight, task)) {
        _inFlight = null;
        _inFlightKey = null;
      }
    }
  }

  Future<GeoPoint?> _request(String address) async {
    await _throttle();
    try {
      final resp = await _dio.get('/v3/geocode/geo', queryParameters: {
        'address': address,
        'key': amapWebKey,
        // 输出更详细一些便于排查
        'extensions': 'base',
      });
      final data = resp.data;
      if (data is! Map) return null;

      final status = '${data['status']}';
      final infos = data['infoc'] ?? data['info'];
      if (status != '1') {
        debugPrint('AmapGeocoding 失败 $address: ${data['info'] ?? infos}');
        return null;
      }
      final geocodes = data['geocodes'];
      if (geocodes is! List || geocodes.isEmpty) return null;
      final first = geocodes.first;
      if (first is! Map) return null;
      final loc = '${first['location']}';
      final parts = loc.split(',');
      if (parts.length != 2) return null;
      final lon = double.tryParse(parts[0]);
      final lat = double.tryParse(parts[1]);
      if (lat == null || lon == null) return null;

      final point = GeoPoint(
        latitude: lat,
        longitude: lon,
        formatted: '${first['formatted_address'] ?? address}',
      );
      await _writeCache(address, point);
      return point;
    } catch (e) {
      debugPrint('AmapGeocoding 异常 $address: $e');
      return null;
    }
  }

  Future<void> _throttle() async {
    final last = _lastCall;
    if (last != null) {
      final elapsed = DateTime.now().difference(last);
      if (elapsed < _minInterval) {
        await Future.delayed(_minInterval - elapsed);
      }
    }
    _lastCall = DateTime.now();
  }

  Future<GeoPoint?> _readCache(String address) async {
    final raw = await _db.getSetting('$_cachePrefix$address');
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw);
      if (m is Map && m['lat'] != null && m['lon'] != null) {
        return GeoPoint(
          latitude: (m['lat'] as num).toDouble(),
          longitude: (m['lon'] as num).toDouble(),
          formatted: '${m['f'] ?? address}',
        );
      }
    } catch (_) {}
    return null;
  }

  Future<void> _writeCache(String address, GeoPoint p) =>
      _db.setSetting('$_cachePrefix$address', jsonEncode({
        'lat': p.latitude,
        'lon': p.longitude,
        'f': p.formatted,
      }));

  /// 批量回填：把坐标缺失的足迹逐个解析并写入。
  /// 返回修复条数。串行执行以避开 QPS 限制。
  Future<int> backfillMissingFootprints() async {
    final missing = await _db.getFootprintsWithoutCoords();
    var fixed = 0;
    for (final f in missing) {
      final p = await locate(f.cityName);
      if (p == null) continue;
      await _db.setFootprintCoords(f.id, p.latitude, p.longitude);
      fixed++;
    }
    return fixed;
  }
}

final amapGeocodingProvider = Provider<AmapGeocodingService>(
    (ref) => AmapGeocodingService(ref.watch(databaseProvider)));
