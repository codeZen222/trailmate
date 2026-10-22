import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_background.dart';
import '../../core/theme/theme_provider.dart';
import '../../core/constants/api_constants.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/weather_constants.dart';
import '../../core/router/app_router.dart';
import '../../providers/database_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/sprite_provider.dart';
import '../../models/sprite_form.dart';
import '../../services/ai_service.dart';
import '../../services/export_service.dart';
import '../../widgets/common/update_dialog.dart';
import 'feedback_page.dart';
import '../../models/trip_model.dart';
import '../../utils/date_utils.dart' as date_utils;

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _apiUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController();
  final _visionModelController = TextEditingController();
  final _weatherKeyController = TextEditingController();
  final _weatherHostController = TextEditingController();
  bool _showApiKey = false;
  bool _isLoading = true;
  bool _testing = false;
  (bool, String)? _testResult;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final db = ref.read(databaseProvider);
    final apiUrl = await db.getSetting('api_base_url');
    final apiKey = await db.getSetting('api_key');
    final model = await db.getSetting('api_model');
    final vision = await db.getSetting('api_vision_model');
    final wKey = await db.getSetting('weather_api_key');
    final wHost = await db.getSetting('weather_api_host');
    if (mounted) {
      _apiUrlController.text = apiUrl ?? defaultApiBaseUrl;
      _apiKeyController.text = apiKey ?? '';
      _modelController.text = model ?? defaultModel;
      _visionModelController.text = vision ?? defaultVisionModel;
      _weatherKeyController.text = wKey ?? '';
      _weatherHostController.text = wHost ?? '';
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _apiUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    _visionModelController.dispose();
    _weatherKeyController.dispose();
    _weatherHostController.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    final db = ref.read(databaseProvider);
    await db.setSetting('api_base_url', _apiUrlController.text.trim());
    await db.setSetting('api_key', _apiKeyController.text.trim());
    await db.setSetting('api_model', _modelController.text.trim());
    await db.setSetting('api_vision_model', _visionModelController.text.trim());
    await db.setSetting('weather_api_key', _weatherKeyController.text.trim());
    await db.setSetting('weather_api_host', _weatherHostController.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('设置已保存')),
      );
    }
  }

  Future<void> _runTestConnection() async {
    // 先把当前输入落库，保证测试用的是最新配置
    final db = ref.read(databaseProvider);
    await db.setSetting('api_base_url', _apiUrlController.text.trim());
    await db.setSetting('api_key', _apiKeyController.text.trim());
    await db.setSetting('api_model', _modelController.text.trim());
    await db.setSetting('api_vision_model', _visionModelController.text.trim());
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final svc = ref.read(aiServiceProvider);
    final result = await svc.testConnection();
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = result;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.$1 ? '✅ ${result.$2}' : '❌ ${result.$2}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 我的旅行档案
                _ProfileEntry(),
                const SizedBox(height: 16),

                // 外观
                _SectionHeader(title: '🎨 外观'),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.palette_outlined),
                        title: const Text('主题风格'),
                        subtitle: Text(ref.watch(appThemeProvider).label),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _showThemePicker(),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      SwitchListTile(
                        secondary: Icon(
                          ref.watch(themeModeProvider) == ThemeMode.dark
                              ? Icons.dark_mode
                              : Icons.light_mode,
                        ),
                        title: const Text('深色模式'),
                        subtitle:
                            Text(_themeModeLabel(ref.watch(themeModeProvider))),
                        value: ref.watch(themeModeProvider) != ThemeMode.light,
                        onChanged: (_) {
                          ref.read(themeModeProvider.notifier).cycle();
                        },
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      SwitchListTile(
                        secondary: const Icon(Icons.auto_fix_high_outlined),
                        title: const Text('日志心情特效'),
                        subtitle: Text(
                          ref.watch(effectsProvider)
                              ? '有动画（已尊重系统「减弱动态效果」）'
                              : '已关闭：仅显示心情徽章',
                        ),
                        value: ref.watch(effectsProvider),
                        onChanged: (v) =>
                            ref.read(effectsProvider.notifier).setEnabled(v),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.image_outlined, size: 18),
                                const SizedBox(width: 10),
                                Text('背景画面',
                                    style: Theme.of(context).textTheme.titleSmall),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final s in BackgroundStyle.values)
                                  ChoiceChip(
                                    selected:
                                        ref.watch(backgroundProvider) == s,
                                    showCheckmark: false,
                                    avatar: Icon(_bgIcon(s), size: 16),
                                    label: Text('${s.label} · ${s.desc}'),
                                    onSelected: (_) => ref
                                        .read(backgroundProvider.notifier)
                                        .set(s),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 旅行精灵
                const _SectionHeader(title: '🧚 旅行精灵'),
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        secondary: const Icon(Icons.spa_outlined),
                        title: const Text('悬浮小精灵'),
                        subtitle: const Text(
                          '常驻各页，可拖拽吸边；点它聊天或说「午餐45」直接记账\n'
                          '写日志时会自动隐藏，不挡字',
                          style: TextStyle(height: 1.4),
                        ),
                        value: ref.watch(spriteProvider).enabled,
                        onChanged: (v) =>
                            ref.read(spriteProvider.notifier).setEnabled(v),
                      ),
                      if (ref.watch(spriteProvider).enabled) ...[
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('形象',
                                  style: Theme.of(context).textTheme.labelLarge),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final f in SpriteForm.values)
                                    ChoiceChip(
                                      selected:
                                          ref.watch(spriteProvider).form == f,
                                      avatar: Icon(f.icon, size: 17),
                                      label: Text('${f.name} · ${f.label}'),
                                      onSelected: (_) => ref
                                          .read(spriteProvider.notifier)
                                          .setForm(f),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (hardcodedApiKey.isEmpty) ...[
                  _SectionHeader(title: '🤖 AI 设置'),
                  Card(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          child: TextField(
                            controller: _apiUrlController,
                            decoration: const InputDecoration(
                              labelText: 'API Base URL',
                              hintText: defaultApiBaseUrl,
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: TextField(
                            controller: _apiKeyController,
                            obscureText: !_showApiKey,
                            decoration: InputDecoration(
                              labelText: 'API Key',
                              border: const OutlineInputBorder(),
                              isDense: true,
                              suffixIcon: IconButton(
                                icon: Icon(_showApiKey
                                    ? Icons.visibility_off
                                    : Icons.visibility),
                                onPressed: () =>
                                    setState(() => _showApiKey = !_showApiKey),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: TextField(
                            controller: _modelController,
                            decoration: const InputDecoration(
                              labelText: '模型名称（文本）',
                              hintText: defaultModel,
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: TextField(
                            controller: _visionModelController,
                            decoration: const InputDecoration(
                              labelText: '视觉模型（图片描述）',
                              hintText: defaultVisionModel,
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.wifi_tethering),
                          title: const Text('测试连接'),
                          subtitle: _testing ? const Text('正在测试...') : null,
                          trailing: _testResult == null
                              ? const Icon(Icons.chevron_right)
                              : Icon(
                                  (_testResult!.$1)
                                      ? Icons.check_circle
                                      : Icons.error,
                                  color: (_testResult!.$1)
                                      ? Colors.green
                                      : Colors.red,
                                ),
                          onTap: _testing ? null : _runTestConnection,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // 天气服务（仅当未写死 Key 时显示，供高级用户自填）
                if (hardcodedWeatherApiKey.isEmpty) ...[
                  _SectionHeader(title: '🌤️ 天气服务'),
                  Card(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '填写后可在写日志定位时自动获取实时天气。使用和风天气（QWeather），个人开发免费额度充足。',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color:
                                        Theme.of(context).colorScheme.outline,
                                  ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: TextField(
                            controller: _weatherKeyController,
                            obscureText: !_showApiKey,
                            decoration: InputDecoration(
                              labelText: '天气 API Key',
                              border: const OutlineInputBorder(),
                              isDense: true,
                              suffixIcon: IconButton(
                                icon: Icon(_showApiKey
                                    ? Icons.visibility_off
                                    : Icons.visibility),
                                onPressed: () =>
                                    setState(() => _showApiKey = !_showApiKey),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: TextField(
                            controller: _weatherHostController,
                            decoration: const InputDecoration(
                              labelText: 'API Host',
                              hintText: 'xxxxxx.qweatherapi.com',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        ListTile(
                          leading: const Icon(Icons.help_outline),
                          title: const Text('如何获取？'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _showWeatherHelp,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // 数据
                _SectionHeader(title: '💾 数据'),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.download_outlined),
                        title: const Text('导出 JSON'),
                        onTap: () => _exportData('json'),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      ListTile(
                        leading: const Icon(Icons.description_outlined),
                        title: const Text('导出 Markdown'),
                        onTap: () => _exportData('markdown'),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      ListTile(
                        leading: const Icon(Icons.picture_as_pdf_outlined),
                        title: const Text('导出 PDF'),
                        onTap: () => _exportData('pdf'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 关于
                _SectionHeader(title: 'ℹ️ 关于'),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.info_outline),
                        title: const Text('版本号'),
                        // 用常量而非写死字符串，发版时只需改 app_constants 一处
                        subtitle: Text('v$appVersion'),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      ListTile(
                        leading: const Icon(Icons.system_update_alt),
                        title: const Text('检查更新'),
                        subtitle: Text('打开下载页 · 访问密码 $kDownloadPassword'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _checkUpdate,
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      ListTile(
                        leading: const Icon(Icons.feedback_outlined),
                        title: const Text('反馈与使用感受'),
                        subtitle: const Text('复制给我，或匿名填写在线问卷'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _showFeedback,
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      ListTile(
                        leading: const Icon(Icons.code),
                        title: const Text('开源许可'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _showLicense(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // 保存按钮
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saveSettings,
                    child: const Text('保存设置'),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
    );
  }

  void _showThemePicker() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择主题'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: AppTheme.values
              .map((theme) => RadioListTile<AppTheme>(
                    title: Text(theme.label),
                    value: theme,
                    groupValue: ref.watch(appThemeProvider),
                    onChanged: (val) {
                      if (val != null) {
                        ref.read(appThemeProvider.notifier).select(val);
                        Navigator.pop(ctx);
                      }
                    },
                  ))
              .toList(),
        ),
      ),
    );
  }

  String _themeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return '浅色模式';
      case ThemeMode.dark:
        return '深色模式';
      case ThemeMode.system:
        return '跟随系统';
    }
  }

  void _showWeatherHelp() {
    const steps = [
      ('1', '打开和风天气控制台 dev.qweather.com，用邮箱注册账号'),
      ('2', '进入「控制台 → 项目管理」，新建一个项目'),
      ('3', '在项目里点「凭据」→ 创建凭据，复制生成的 API Key'),
      (
        '4',
        '在「设置 → 开发文档 → API Host」找到你的专属 Host（形如 abc123.qweatherapi.com），复制它'
      ),
      ('5', '把 Key 和 Host 分别填到上面的输入框，保存即可'),
    ];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('获取天气 API'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: steps
                .map((s) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                              radius: 11,
                              child: Text(s.$1,
                                  style: const TextStyle(fontSize: 12))),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Text(s.$2,
                                  style: Theme.of(ctx).textTheme.bodyMedium)),
                        ],
                      ),
                    ))
                .toList(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  void _exportData(String format) async {
    if (format == 'json') {
      await _runExport(
          () => ref.read(exportServiceProvider).exportJson(), 'JSON');
    } else if (format == 'markdown' || format == 'pdf') {
      final trip = await _pickTrip();
      if (trip == null) return;
      if (format == 'markdown') {
        await _runExport(
            () => ref.read(exportServiceProvider).exportMarkdown(trip.id),
            'Markdown');
      } else {
        await _runExport(
            () => ref.read(exportServiceProvider).exportPdf(trip.id), 'PDF');
      }
    }
  }

  Future<void> _runExport(Future<String> Function() task, String label) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('正在导出 $label...')),
    );
    try {
      final path = await task();
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('$label 导出成功'),
          content: SingleChildScrollView(child: Text(path)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('知道了')),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label 导出失败：$e')),
      );
    }
  }

  /// 弹出一个旅程选择列表，返回选中的 Trip（取消返回 null）。
  Future<Trip?> _pickTrip() async {
    final trips = await ref.read(databaseProvider).getAllTrips();
    if (!mounted) return null;
    if (trips.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('还没有可导出的旅程')),
      );
      return null;
    }
    final modelTrips = trips
        .map((t) => Trip(
              id: t.id,
              destination: t.destination,
              coverPath: t.coverPath,
              startDate: t.startDate,
              endDate: t.endDate,
              rating: t.rating,
              notes: t.notes,
              isCompleted: t.isCompleted,
              createdAt: t.createdAt,
              updatedAt: t.updatedAt,
            ))
        .toList();
    return showModalBottomSheet<Trip>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('选择要导出的旅程',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: modelTrips
                    .map((t) => ListTile(
                          leading: const Icon(Icons.luggage_outlined),
                          title: Text(t.destination),
                          subtitle: Text(date_utils.formatDateRange(
                              t.startDate, t.endDate)),
                          onTap: () => Navigator.pop(ctx, t),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 手动检查更新：给明确的转圈与结果反馈。
  /// 反馈页。用 push 而不是命名路由 —— 只有一个入口，不值得为它加路由表分支。
  void _showFeedback() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FeedbackPage()),
    );
  }

  /// 手动检查更新 —— 直接打开下载页。
  ///
  /// 【为什么不做自动版本检测】曾尝试过三个方案，全部因国内网络不可达而失败：
  ///   · GitHub Releases      → 手机打不开 github
  ///   · Cloudflare workers.dev → DNS 被污染（实测解析到 Facebook IP、100% 丢包）
  ///   · jsDelivr CDN          → 本机三节点握手全失败，且其国内可用性本就不稳定
  /// 自定义域名需付费 + 实名审核，对十几个用户的规模不划算。
  /// 所以退回到最朴素的方案：点了就跳蓝奏云，用户自己看有没有新版。
  Future<void> _checkUpdate() async {
    await UpdateNavigator.openDownload(context, kDownloadUrl);
  }

  void _showLicense() {
    showLicensePage(
      context: context,
      applicationName: appName,
      applicationVersion: appVersion,
    );
  }
}

IconData _bgIcon(BackgroundStyle s) => switch (s) {
      BackgroundStyle.scene => Icons.filter_vintage_outlined,
      BackgroundStyle.gradient => Icons.gradient_outlined,
      BackgroundStyle.flat => Icons.crop_square_outlined,
    };

class _ProfileEntry extends ConsumerWidget {
  const _ProfileEntry();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final profile = ref.watch(profileProvider);
    final filled = profile != null;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: cs.primaryContainer,
            border: Border.all(color: cs.outlineVariant.withAlpha(90)),
          ),
          clipBehavior: Clip.antiAlias,
          child: filled && (profile.avatarPath ?? '').isNotEmpty
              ? Image.file(File(profile.avatarPath!), fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      Icon(Icons.person_outline, color: cs.onPrimaryContainer))
              : Icon(filled ? Icons.badge_outlined : Icons.person_outline,
                  color: cs.onPrimaryContainer),
        ),
        title: Text(
          filled ? profile.nickname : '我的旅行档案',
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          filled
              ? ([
                  if ((profile.homeCity ?? '').isNotEmpty) profile.homeCity,
                  if ((profile.bio ?? '').isNotEmpty) profile.bio,
                ].whereType<String>().join(' · '))
              : '未创建 · 点击生成专属旅行卡片',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.pushNamed(context, AppRouter.profile),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}
