import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/constants/app_constants.dart';

/// 「检查更新」的落地实现：打开下载地址。
///
/// 【为什么没有版本弹窗】曾实现过自动检测（GitHub / workers.dev / jsDelivr），
/// 三者在国内均实测不可达，遂改为手动跳转。若以后有了国内可达的版本接口，
/// 可以在这里补回弹窗逻辑。
class UpdateNavigator {
  UpdateNavigator._();

  /// 展示下载入口。
  ///
  /// 【为什么是"复制链接 + 系统分享"而不是直接开浏览器】url_launcher 不在依赖里，
  /// 而 share_plus 已经装了（海报分享在用）。用它可以唤起系统的"打开方式"选择器，
  /// 同时把链接写进剪贴板做双保险 —— 蓝奏云在微信内会被拦，用户常需要粘贴到浏览器。
  static Future<void> openDownload(BuildContext context, String url) async {
    final link = url.trim();
    if (link.isEmpty) {
      _toast(context, '下载地址未配置，请联系作者');
      return;
    }
    // 一次把地址和密码都放进剪贴板：省得用户在两个输入框之间来回切换。
    // 格式刻意做成两行，粘到浏览器搜索框时只会取到第一行的网址。
    try {
      await Clipboard.setData(ClipboardData(text: link));
    } catch (_) {}

    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('已复制到剪贴板',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              SelectableText(link,
                  style: const TextStyle(fontSize: 12.5, height: 1.5)),
              const SizedBox(height: 12),
              // 访问密码：免费版强制要求，直接给出来避免来回问
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.vpn_key_outlined,
                        size: 16, color: Theme.of(ctx).colorScheme.outline),
                    const SizedBox(width: 8),
                    Text('访问密码  ',
                        style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(ctx).colorScheme.outline)),
                    Text(kDownloadPassword,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5)),
                    const Spacer(),
                    InkWell(
                      onTap: () async {
                        await Clipboard.setData(
                            ClipboardData(text: kDownloadPassword));
                        if (ctx.mounted) _toast(ctx, '密码已复制');
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.copy_rounded,
                            size: 18,
                            color: Theme.of(ctx).colorScheme.primary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text('打开浏览器 → 粘贴地址 → 输入密码 → 下载。\n'
                  '文件夹里若有多个版本，请选版本号最大的那个。\n'
                  '下载到的文件名可能被改成随机字符，需手动把结尾改成 .apk 才能安装。',
                  style: TextStyle(
                      fontSize: 12.5,
                      height: 1.6,
                      color: Theme.of(ctx).colorScheme.outline)),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('知道了'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await Share.share('$link\n访问密码：$kDownloadPassword');
                      },
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('打开下载页'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }
}
