import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/weather_constants.dart';
import '../providers/database_provider.dart';
import 'ai_service.dart' show dioProvider;

/// 天气查询结果（已映射成 App 内的展示格式）。
class WeatherResult {
  final String text; // 原始中文描述，如「少云」
  final String category; // 归类：晴/多云/阴/雨/雪/雾/风
  final int tempC; // 摄氏温度（整数）
  const WeatherResult(
      {required this.text, required this.category, required this.tempC});

  /// 与手动选择器一致的显示串，例如 "⛅ 多云"。
  String get display => '${WeatherService.getEmoji(category)} $category';
}

class WeatherService {
  static const Map<String, String> weatherIcons = {
    '晴': '☀️',
    '多云': '⛅',
    '阴': '☁️',
    '雨': '🌧️',
    '雪': '❄️',
    '雾': '🌫️',
    '风': '🌬️',
  };

  static const List<String> weatherOptions = [
    '☀️ 晴',
    '⛅ 多云',
    '☁️ 阴',
    '🌧️ 雨',
    '❄️ 雪',
    '🌫️ 雾',
    '🌬️ 风',
  ];

  static String getIcon(String weather) => weatherIcons[weather] ?? '🌤️';

  static String getEmoji(String weather) {
    for (final option in weatherOptions) {
      if (option.contains(weather)) return option.split(' ')[0];
    }
    return '🌤️';
  }

  /// 把和风 condition.code 归入 App 的天气类别。
  /// 参考 https://dev.qweather.com/docs/api/weather/weather-conditions/
  static String _categorizeCode(String code) {
    final c = int.tryParse(code) ?? -1;
    if (c == 100) return '晴'; // Sunny
    if (c == 101 || c == 102 || c == 103) return '多云'; // Cloudy / Few / Partly Clouds
    if (c == 104) return '阴'; // Overcast
    if (c >= 300 && c <= 399) return '雨'; // 阵雨、雷阵雨、各级降雨
    if (c >= 400 && c <= 499) return '雪'; // 各级降雪、雨夹雪
    if (c == 500 || c == 501 || c >= 509) return '雾'; // Mist/Fog/Dense Fog...
    if (c == 502 || c == 511 || c == 512 || c == 513) return '阴'; // Haze 类
    if (c >= 503 && c <= 508) return '风'; // Sand/Dust/Duststorm/Sandstorm
    if (c == 900) return '晴'; // Hot
    if (c == 901) return '阴'; // Cold
    return '多云'; // Unknown 等兜底
  }
}

/// 带配置的实时天气获取（需用户在设置里填 Key + Host）。
class WeatherFetcher {
  final Dio _dio;
  final Ref _ref;
  WeatherFetcher(this._dio, this._ref);

  bool get isConfigured {
    // 同步判断不可用（配置在 DB），交由调用方处理未配置提示。
    return true;
  }

  Future<(bool ok, String? message, WeatherResult? result)> fetchCurrent(
      double lat, double lon) async {
    final db = _ref.read(databaseProvider);
    // 优先用写死的常量；为空时回退到设置页用户自填的值。
    final key = hardcodedWeatherApiKey.isNotEmpty
        ? hardcodedWeatherApiKey
        : await db.getSetting(weatherApiKeySettingKey);
    final host = hardcodedWeatherApiHost.isNotEmpty
        ? hardcodedWeatherApiHost
        : await db.getSetting(weatherApiHostSettingKey);
    if (key == null || key.isEmpty || host == null || host.isEmpty) {
      return (false, '天气接口未配置（缺少 API Key / Host）', null);
    }
    final base = host.startsWith('http') ? host : 'https://$host';
    try {
      // 用兼容性最好的 v7 端点：location 为 "经度,纬度"，key 走 query。
      final resp = await _dio.get(
        '$base/v7/weather/now',
        queryParameters: {
          'location': '${lon.toStringAsFixed(2)},${lat.toStringAsFixed(2)}',
          'lang': 'zh',
          'key': key,
        },
        options: Options(
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
        ),
      );
      final data = resp.data;
      if (data is! Map) return (false, '返回格式异常', null);
      // v7 结构：{ code:"200", now:{ text, icon, temp } }
      final now = data['now'];
      if (now is! Map) {
        return (false, '天气接口无数据（检查 Key/Host）', null);
      }
      final code = now['icon']?.toString() ?? '';
      final text = now['text']?.toString() ?? '';
      final tempVal = num.tryParse(now['temp']?.toString() ?? '');
      final cat = WeatherService._categorizeCode(code);
      final result = WeatherResult(
        text: text.isEmpty ? cat : text,
        category: cat,
        tempC: tempVal?.round() ?? 0,
      );
      return (true, null, result);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        return (false, 'API Key 或 Host 无效', null);
      }
      if (status != null) return (false, '天气接口错误($status)', null);
      return (false, '网络超时，请检查天气接口地址', null);
    } catch (e) {
      return (false, '获取天气失败：$e', null);
    }
  }
}

final weatherFetcherProvider = Provider<WeatherFetcher>(
    (ref) => WeatherFetcher(ref.watch(dioProvider), ref));
