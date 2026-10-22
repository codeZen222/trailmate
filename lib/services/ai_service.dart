import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/api_constants.dart';
import '../providers/database_provider.dart';

/// AI 服务：写作润色 / 智能标签 / 每日总结。
/// 配置（api_key / api_base_url / api_model）在每次调用前从 settings 表读取，
/// 未配置时优雅降级，不影响核心功能。
class AiService {
  final Dio _dio;
  final Ref _ref;

  AiService(this._dio, this._ref);

  Future<_AiConfig> _loadConfig() async {
    final db = _ref.read(databaseProvider);
    // 优先用写死的常量 Key；为空时回退到设置页用户自填的值。
    final key = hardcodedApiKey.isNotEmpty
        ? hardcodedApiKey
        : await db.getSetting('api_key');
    final base = await db.getSetting('api_base_url');
    final model = await db.getSetting('api_model');
    final vision = await db.getSetting('api_vision_model');
    return _AiConfig(
      apiKey: (key == null || key.isEmpty) ? null : key,
      baseUrl: _normalizeBase((base == null || base.isEmpty) ? defaultApiBaseUrl : base),
      model: (model == null || model.isEmpty) ? defaultModel : model,
      visionModel: (vision == null || vision.isEmpty) ? defaultVisionModel : vision,
    );
  }

  /// 容错处理用户手填的 Base URL。
  ///
  /// 【为什么需要】常见误填是把控制台里的完整地址（少了 /compatible-mode/v1）
  /// 或多带了 /chat/completions 粘进来，结果请求打到不存在的路径上返回 404，
  /// 报出来却是"接口地址不存在"，很难联想到是自己填错了。
  static String _normalizeBase(String raw) {
    var b = raw.trim();
    if (b.isEmpty) return defaultApiBaseUrl;
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    // 用户直接贴了完整接口地址：剥掉尾巴，只留版本前缀
    for (final suffix in ['/chat/completions', '/completions', '/responses']) {
      if (b.endsWith(suffix)) {
        b = b.substring(0, b.length - suffix.length);
        break;
      }
    }
    // 明显缺少 OpenAI 兼容路径时补上（仅针对百炼类域名，避免乱猜自建服务）
    if (!b.endsWith('/v1') && !b.contains('/v1/')) {
      if (b.contains('aliyuncs.com') || b.contains('dashscope')) {
        b = '$b/compatible-mode/v1';
      } else {
        b = '$b/v1';
      }
    }
    return b;
  }

  bool _ready(_AiConfig c) => c.apiKey != null && c.apiKey!.isNotEmpty;

  /// 测试连接：发一个极短请求验证 Key/URL/模型是否可用。
  Future<(bool ok, String message)> testConnection() async {
    final c = await _loadConfig();
    if (!_ready(c)) return (false, '尚未填写 API Key');
    try {
      await _chat(c, 'ping', system: '只回复一个字：好', maxTokens: 8);
      return (true, '连接成功');
    } catch (e) {
      return (false, _friendlyError(e));
    }
  }

  Future<String> polishWriting(String draft, {String? style}) async {
    final c = await _loadConfig();
    if (!_ready(c)) return _notConfigured;
    try {
      final sys = '你是一个旅行日志写作助手。请根据用户输入的关键词或草稿，'
          '润色扩写成优美自然的游记文字。保持真实感和个人化，200字以内。'
          '${style != null ? '风格偏好：$style。' : ''}';
      return await _chat(c, draft, system: sys);
    } catch (e) {
      return _callFailed(e);
    }
  }

  Future<List<String>> suggestTags(String content) async {
    final c = await _loadConfig();
    if (!_ready(c)) return ['美食', '风景'];
    try {
      final raw = await _chat(
        c,
        content,
        system: '分析以下旅行日志内容，返回3-5个相关标签。'
            '只输出 JSON 数组字符串，例如 ["美食","古城"]，不要多余解释。',
      );
      return _parseTagArray(raw);
    } catch (_) {
      return ['美食', '风景'];
    }
  }

  Future<String> dailySummary(String logs) async {
    final c = await _loadConfig();
    if (!_ready(c)) return _notConfigured;
    try {
      return await _chat(
        c,
        logs,
        system: '你是一个旅行日志助手。根据用户提供的当天日志内容，'
            '生成一份简洁的每日总结，100字以内。',
      );
    } catch (e) {
      return _callFailed(e);
    }
  }

  /// 该端点上实测可用的视觉模型（按优先级）。
  ///
  /// 【为什么要列表回退】不同开通范围下可用模型差别很大：实测本 Key
  ///   qwen3-vl-plus ✅ / qwen-vl-ocr ✅ / qwen3-vl-flash ❌404 / qwen-vl-max ❌404
  ///   qwen-vl-max-latest ❌403 / qwen2.5-vl-72b ❌403
  /// 用户在设置里填错一个名字就整个功能不可用；自动按序试一遍比让他猜强。
  static const List<String> _visionFallbacks = [
    'qwen3-vl-plus',
    'qwen-vl-ocr',
  ];

  /// 2.6：图片描述（多模态）。需要模型支持 image_url 输入。
  Future<String> describeImage(String imagePath) async {
    final c = await _loadConfig();
    if (!_ready(c)) return _notConfigured;
    try {
      final file = File(imagePath);
      if (!await file.exists()) throw StateError('图片不存在');
      final raw = await file.readAsBytes();
      // 手机原图常 4-8MB，base64 后请求体再膨胀约 33%，既慢又容易触发网关限制。
      // 视觉模型不需要原始分辨率，压到长边 1280 已足够写出好描述。
      final Uint8List bytes = await _downscaleForVision(raw);
      // 压缩后统一是 PNG（Dart 侧 ui.ImageByteFormat 只到 PNG，没有 JPEG 编码器）
      final dataUri = 'data:image/png;base64,${base64Encode(bytes)}';

      // 依次尝试：用户指定 → 内置默认 → 已知可用列表（去重）
      final tried = <String>{};
      Object? lastError;
      for (final model in [c.visionModel, defaultVisionModel, ..._visionFallbacks]) {
        if (model.isEmpty || !tried.add(model)) continue;
        try {
          return await _describeWithModel(c, model, dataUri);
        } on DioException catch (e) {
          final code = e.response?.statusCode;
          // 只有"模型不存在/无权限"才值得换下一个；网络问题换了也没用
          if (code != 404 && code != 403) rethrow;
          lastError = e;
        }
      }
      throw lastError ?? StateError('无可用视觉模型');
    } catch (e) {
      return _callFailed(e);
    }
  }

  Future<String> _describeWithModel(
      _AiConfig c, String model, String dataUri) async {
    final resp = await _dio.post(
      '${c.baseUrl}/chat/completions',
      options: Options(
        headers: {'Authorization': 'Bearer ${c.apiKey}'},
        sendTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 90),
      ),
      data: {
        'model': model,
        'max_tokens': 300,
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': '请用一句话生动地描述这张旅行照片的内容与氛围。'},
              {'type': 'image_url', 'image_url': {'url': dataUri}},
            ],
          },
        ],
      },
    );
    final data = resp.data;
    final choices = data is Map ? data['choices'] : null;
    if (choices is List && choices.isNotEmpty) {
      final msg = choices.first['message'];
      if (msg is Map && msg['content'] != null) {
        return msg['content'].toString().trim();
      }
    }
    throw StateError('AI 返回格式异常');
  }

  /// 把图片缩到长边不超过 [maxSide] 并转成 JPEG，用于喂给视觉模型。
  ///
  /// 【为什么要压】实测该接口本身没问题（小图 2.4s、大图 4.1s 都能返回），
  /// 但手机原图 base64 后动辄几 MB，上传慢、也更接近网关的请求体上限。
  /// 任何一步失败都退回原始字节 —— 描述功能不该因为压缩失败而整体不可用。
  Future<Uint8List> _downscaleForVision(Uint8List bytes,
      {int maxSide = 1280}) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final longSide = math.max(img.width, img.height);
      if (longSide == 0) return bytes;

      final scale = longSide <= maxSide ? 1.0 : maxSide / longSide;
      final w = math.max(1, (img.width * scale).round());
      final h = math.max(1, (img.height * scale).round());

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawImageRect(
        img,
        ui.Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.medium,
      );
      final scaled = recorder.endRecording().toImageSync(w, h);
      img.dispose();
      codec.dispose();

      final data = await scaled.toByteData(format: ui.ImageByteFormat.png);
      scaled.dispose();
      if (data == null) return bytes;
      // Dart 侧只能直接编 PNG；PNG 比 JPEG 大，但仍远小于原图，
      // 且服务端对 image/png 同样支持。
      return data.buffer.asUint8List();
    } catch (_) {
      return bytes;
    }
  }

  /// 2.8：流式多轮对话。onChunk 每次收到一段增量文本即回调；返回完整文本或错误标记串。
  Future<String> chatStream(
    List<Map<String, String>> history, {
    required void Function(String delta) onChunk,
    CancelToken? cancelToken,
  }) async {
    final c = await _loadConfig();
    if (!_ready(c)) return _notConfigured;
    final sb = StringBuffer();
    try {
      final resp = await _dio.post(
        '${c.baseUrl}/chat/completions',
        cancelToken: cancelToken,
        options: Options(
          headers: {'Authorization': 'Bearer ${c.apiKey}'},
          responseType: ResponseType.stream,
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 120),
        ),
        data: {
          'model': c.model,
          'max_tokens': 1000,
          'stream': true,
          'messages': [
            {'role': 'system', 'content': '你是 TrailMate 旅行助手，帮助用户规划行程、推荐目的地、解答旅行问题。回答简洁友好，中文为主。'},
            ...history.map((m) => {'role': m['role'], 'content': m['content']}),
          ],
        },
      );
      final body = resp.data as ResponseBody;
      final stream = body.stream;
      const decoder = Utf8Decoder(allowMalformed: true);
      var buffer = '';
      await for (final bytes in stream) {
        buffer += decoder.convert(bytes as List<int>);
        // 按行解析 SSE
        while (buffer.contains('\n')) {
          final idx = buffer.indexOf('\n');
          final line = buffer.substring(0, idx).trim();
          buffer = buffer.substring(idx + 1);
          if (!line.startsWith('data:')) continue;
          final payload = line.substring(5).trim();
          if (payload == '[DONE]') break;
          try {
            final json = jsonDecode(payload);
            final choices = json['choices'];
            if (choices is List && choices.isNotEmpty) {
              final delta = choices.first['delta'];
              if (delta is Map && delta['content'] != null) {
                final piece = delta['content'].toString();
                sb.write(piece);
                onChunk(piece);
              }
            }
          } catch (_) {/* 跳过不完整片段 */}
        }
      }
      if (sb.isEmpty) throw StateError('AI 未返回内容');
      return sb.toString().trim();
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) return '__CANCELLED__';
      return _callFailed(e);
    }
  }

  /// 2.8：多轮对话助手，接受完整历史消息。
  Future<String> chatWithHistory(List<Map<String, String>> history) async {
    final c = await _loadConfig();
    if (!_ready(c)) return _notConfigured;
    try {
      final resp = await _dio.post(
        '${c.baseUrl}/chat/completions',
        options: Options(
          headers: {'Authorization': 'Bearer ${c.apiKey}'},
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 90),
        ),
        data: {
          'model': c.model,
          'max_tokens': 1000,
          'messages': [
            {'role': 'system', 'content': '你是 TrailMate 旅行助手，帮助用户规划行程、推荐目的地、解答旅行问题。回答简洁友好，中文为主。'},
            ...history.map((m) => {'role': m['role'], 'content': m['content']}),
          ],
        },
      );
      final data = resp.data;
      final choices = data is Map ? data['choices'] : null;
      if (choices is List && choices.isNotEmpty) {
        final msg = choices.first['message'];
        if (msg is Map && msg['content'] != null) return msg['content'].toString().trim();
      }
      throw StateError('AI 返回格式异常');
    } catch (e) {
      return _callFailed(e);
    }
  }

  // ---- 内部：统一走 OpenAI 兼容的 chat/completions ----
  Future<String> _chat(_AiConfig c, String user, {required String system, int maxTokens = 800}) async {
    final resp = await _dio.post(
      '${c.baseUrl}/chat/completions',
      options: Options(headers: {'Authorization': 'Bearer ${c.apiKey}'}, sendTimeout: const Duration(seconds: 30), receiveTimeout: const Duration(seconds: 60)),
      data: {
        'model': c.model,
        'max_tokens': maxTokens,
        'messages': [
          {'role': 'system', 'content': system},
          {'role': 'user', 'content': user},
        ],
      },
    );
    final data = resp.data;
    final choices = data is Map ? data['choices'] : null;
    if (choices is List && choices.isNotEmpty) {
      final msg = choices.first['message'];
      if (msg is Map && msg['content'] != null) return msg['content'].toString().trim();
    }
    throw StateError('AI 返回格式异常');
  }

  List<String> _parseTagArray(String raw) {
    // 容错：截取第一个 [ ... ] 再解码
    final start = raw.indexOf('[');
    final end = raw.lastIndexOf(']');
    if (start >= 0 && end > start) {
      try {
        final list = jsonDecode(raw.substring(start, end + 1));
        if (list is List) {
          return list.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).take(5).toList();
        }
      } catch (_) {}
    }
    // 退化为按分隔符切
    return raw
        .replaceAll(RegExp(r'[\[\]"“”‘’]'), '')
        .split(RegExp(r'[,，、\s]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .take(5)
        .toList();
  }

  static const _notConfigured = '__NOT_CONFIGURED__';
  String _callFailed(Object e) => '__CALL_FAILED__:${_friendlyError(e)}';

  String _friendlyError(Object e) {
    if (e is DioException) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        return '网络超时，请检查 Base URL 与网络';
      }
      final code = e.response?.statusCode;
      // 服务端的 message 优先于我们的笼统文案：
      // 404 既可能是路径错、也可能是模型名不存在（阿里云回 "Model not exist."），
      // 只报"接口地址不存在"会让人对着正确的 URL 干瞪眼。
      final serverMsg = _serverMessage(e);
      if (code == 401) return 'API Key 无效或未授权${serverMsg ?? ""}';
      if (code == 403) return '该模型未开通访问权限${serverMsg ?? ""}';
      if (code == 404) {
        if (serverMsg != null && serverMsg.contains('Model')) {
          return '模型不可用：$serverMsg\n请在设置里改「视觉模型」';
        }
        return '接口地址不存在，请检查 Base URL（应形如 …/compatible-mode/v1）';
      }
      if (code == 429) return '请求过于频繁或额度不足';
      return '网络错误(${code ?? e.type.name})${serverMsg ?? ""}';
    }
    return e.toString();
  }

  /// 从响应体里抽出错因文本，最多 80 字。
  String? _serverMessage(DioException e) {
    try {
      final d = e.response?.data;
      String? m;
      if (d is Map) {
        final err = d['error'];
        if (err is Map) {
          m = err['message']?.toString();
        } else {
          m = d['message']?.toString() ?? d['msg']?.toString();
        }
      } else if (d is String && d.isNotEmpty) {
        m = d;
      }
      if (m == null || m.trim().isEmpty) return null;
      m = m.trim();
      return '：${m.length > 80 ? '${m.substring(0, 80)}…' : m}';
    } catch (_) {
      return null;
    }
  }
}

class _AiConfig {
  final String? apiKey;
  final String baseUrl;
  final String model;
  final String visionModel;
  _AiConfig({required this.apiKey, required this.baseUrl, required this.model, required this.visionModel});
}

final dioProvider = Provider<Dio>((ref) => Dio());

final aiServiceProvider = Provider<AiService>((ref) => AiService(ref.watch(dioProvider), ref));
