import 'dart:io';

class ImageUtils {
  static const int maxWidth = 1080;

  static Future<File> compressImage(String path) async {
    final file = File(path);
    return file;
  }

  static String getImageName(String path) {
    return path.split('/').last.split('\\').last;
  }

  static String getImageExtension(String path) {
    final name = getImageName(path);
    final parts = name.split('.');
    return parts.length > 1 ? parts.last.toLowerCase() : 'jpg';
  }

  static bool isValidImageExtension(String path) {
    final ext = getImageExtension(path);
    return ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext);
  }
}