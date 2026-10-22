import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 图片持久化。
///
/// 【为什么需要这个】
/// `image_picker` 返回的是**缓存目录**里的临时文件（Android 上形如
/// `.../cache/image_picker/xxx.jpg`）。系统可在空间紧张时回收 cache，
/// **更常见的是：重装/覆盖安装 APK 时 cache 被清空**。
/// 此前代码把该临时路径直接写进数据库，导致照片记录还在、文件却没了。
///
/// 本服务把选中的图片**复制**到应用私有持久目录，再返回持久路径。
class ImageStorage {
  ImageStorage._();

  static const String photosDir = 'trip_photos';
  static const String coversDir = 'trip_covers';
  static const String profileDir = 'profile';

  /// 把临时图片复制到持久目录。失败时退回原路径（本次会话仍可用），不抛异常打断操作。
  static Future<String> persist(String sourcePath, {required String folder}) async {
    try {
      final src = File(sourcePath);
      if (!await src.exists()) return sourcePath;

      final base = await getApplicationDocumentsDirectory();
      final dir = Directory('${base.path}/$folder');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final dot = sourcePath.lastIndexOf('.');
      final ext = dot > 0 && dot > sourcePath.length - 8
          ? sourcePath.substring(dot)
          : '.jpg';
      final name =
          '${DateTime.now().millisecondsSinceEpoch}_${sourcePath.hashCode.abs()}$ext';
      final dest = File('${dir.path}/$name');
      await src.copy(dest.path);
      return dest.path;
    } catch (e) {
      debugPrint('ImageStorage.persist 失败：$e');
      return sourcePath;
    }
  }

  /// 判断路径是否位于易被清空的缓存目录（用于识别历史遗留数据）。
  static bool looksEphemeral(String? path) {
    if (path == null || path.isEmpty) return false;
    final p = path.replaceAll('\\', '/');
    return p.contains('/cache/') || p.contains('image_picker');
  }

  /// 文件是否还存在。
  static Future<bool> exists(String? path) async {
    if (path == null || path.isEmpty) return false;
    try {
      return await File(path).exists();
    } catch (_) {
      return false;
    }
  }
}
