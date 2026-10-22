import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../providers/database_provider.dart';
import '../../widgets/common/update_dialog.dart';

/// 反馈页。
///
/// 【为什么不是单纯一个外链】用户只会写"地图打不开"，你还得追问版本、机型、
/// 哪一步触发的 —— 一来一回往往就放弃了。这里把设备与数据规模信息自动拼进
/// 正文，用户只描述现象即可；同时保留"打开在线表单"作为可选去处。
class FeedbackPage extends ConsumerStatefulWidget {
  const FeedbackPage({super.key});

  @override
  ConsumerState<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends ConsumerState<FeedbackPage> {
  final _text = TextEditingController();

  /// 在线表单地址。留空则不显示"提交到表单"按钮，只用复制方式。
  /// 问卷里同时包含「反馈问题」和「使用感受」两类题。
  static const String _formUrl = kSurveyUrl;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// 组装完整反馈内容：用户描述 + 自动采集的诊断信息。
  Future<String> _compose() async {
    final b = StringBuffer();
    final note = _text.text.trim();
    b.writeln(note.isEmpty ? '（未填写问题描述）' : note);
    b
      ..writeln()
      ..writeln('—— 以下为自动附加信息 ——')
      ..writeln('版本：v$appVersion')
      ..writeln('机型：${_deviceModel()}')
      ..writeln('系统：Android ${_release()}');

    // 数据规模能解释很多问题（比如地图空白可能只是没数据）
    try {
      final db = ref.read(databaseProvider);
      final trips = await db.getAllTrips();
      final footprints = await db.getAllFootprints();
      b
        ..writeln('旅程数：${trips.length}')
        ..writeln('足迹城市数：${footprints.length}');
      final noCoord = footprints.where((f) => f.latitude == 0).length;
      if (noCoord > 0) b.writeln('其中缺坐标：$noCoord 个');
    } catch (_) {
      // 取不到不影响提交，少一行信息而已
    }
    return b.toString();
  }

  String _deviceModel() {
    // dart:io 在 Android 上读不到 Build.MODEL，退而求其次用平台名，
    // 真正的机型让用户自己补一句更可靠。
    if (Platform.isAndroid) return 'Android 手机（可补充具体型号）';
    return Platform.operatingSystem;
  }

  String _release() {
    try {
      return Platform.operatingSystemVersion.split(RegExp(r'\s+\(')).first;
    } catch (_) {
      return '?';
    }
  }

  Future<void> _copyAll() async {
    final body = await _compose();
    await Clipboard.setData(ClipboardData(text: body));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制，粘贴给作者即可')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('反馈问题')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Card(
            color: cs.surfaceContainerHighest.withAlpha(90),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                '遇到闪退、位置不对、图片看不到…都可以说。\n'
                '麻烦一点的话：**在哪一步、点了什么、出现了什么**。',
                style: theme.textTheme.bodySmall?.copyWith(height: 1.7),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _text,
            maxLines: 7,
            decoration: InputDecoration(
              labelText: '问题描述',
              hintText: '例如：足迹地图上泰安的点没有显示，日志里有泰安的照片',
              alignLabelWithHint: true,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Text('下面的设备与数据信息会自动一起发送，不用手写',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.outline)),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: _copyAll,
            icon: const Icon(Icons.copy_all_outlined),
            label: const Text('复制反馈内容'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _preview(context),
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('先看看会发什么'),
          ),
          if (_formUrl.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Divider(),
            const SizedBox(height: 6),
            Text('不想打字？也可以直接填在线问卷（匿名）',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.outline)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => UpdateNavigator.openDownload(context, _formUrl),
              icon: const Icon(Icons.how_to_reg_outlined),
              label: const Text('填写在线问卷'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _preview(BuildContext context) async {
    final body = await _compose();
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('将发送的内容'),
        content: SingleChildScrollView(
          child: SelectableText(body, style: const TextStyle(fontSize: 12.5, height: 1.6)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _copyAll();
            },
            child: const Text('复制'),
          ),
        ],
      ),
    );
  }
}
