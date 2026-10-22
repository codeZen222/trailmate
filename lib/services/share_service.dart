import 'dart:io';
import 'package:share_plus/share_plus.dart';

class ShareService {
  Future<void> shareText(String text) async {
    await Share.share(text);
  }

  Future<void> shareFile(File file, {String? subject}) async {
    await Share.shareXFiles([XFile(file.path)], subject: subject);
  }
}
