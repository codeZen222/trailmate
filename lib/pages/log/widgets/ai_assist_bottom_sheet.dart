import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/ai_service.dart';
import '../../../providers/database_provider.dart';

class AiAssistBottomSheet extends ConsumerStatefulWidget {
  final TextEditingController contentController;
  final int? tripId;

  /// 日志中**已添加**的照片路径。图片描述只能针对这些照片生成 ——
  /// 再让用户从相册另选一张没入库的图毫无意义：描述会随弹窗一起丢掉。
  final List<String> existingPhotos;

  /// 保存生成的描述（path -> description），写回编辑页待落库。
  final void Function(String path, String description)? onDescribePhoto;

  const AiAssistBottomSheet({
    super.key,
    required this.contentController,
    this.tripId,
    this.existingPhotos = const [],
    this.onDescribePhoto,
  });

  @override
  ConsumerState<AiAssistBottomSheet> createState() => _AiAssistBottomSheetState();
}

class _AiAssistBottomSheetState extends ConsumerState<AiAssistBottomSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _draftController = TextEditingController();
  bool _busy = false;
  List<String> _suggestedTags = [];
  String? _pickedImagePath;
  String? _imageDescription;

  static const _notConfigured = '__NOT_CONFIGURED__';
  static const _callFailedPrefix = '__CALL_FAILED__:';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _draftController.dispose();
    super.dispose();
  }

  void _insertText(String text) {
    final current = widget.contentController.text;
    final sel = widget.contentController.selection;
    if (sel.isValid && sel.start >= 0 && sel.end <= current.length) {
      final newText = current.replaceRange(sel.start, sel.end, text);
      widget.contentController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: sel.start + text.length),
      );
    } else {
      final appended = current.isEmpty ? text : '$current\n$text';
      widget.contentController.value = TextEditingValue(
        text: appended,
        selection: TextSelection.collapsed(offset: appended.length),
      );
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 统一的"预览 + 可编辑 + 确认"弹窗。
  /// 返回用户确认后的文本；取消则返回 null。
  /// [insertToBody] 为 true 时同时把文本插入正文（润色/总结等场景）。
  Future<String?> _showPreview({
    required String title,
    required String initialText,
    String confirmLabel = '插入正文',
    bool insertToBody = true,
    String? photoHint,
  }) async {
    final controller = TextEditingController(text: initialText);
    // 归一化空串，便于下游用一次 null 判断即可
    final hint = (photoHint == null || photoHint.trim().isEmpty) ? null : photoHint;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.auto_awesome, size: 18, color: Theme.of(ctx).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 16))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 描述是针对某张已有照片的，标出来免得用户忘了在改哪张
            if (hint != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(Icons.image_outlined, size: 14,
                        color: Theme.of(ctx).colorScheme.outline),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(hint,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                              color: Theme.of(ctx).colorScheme.outline)),
                    ),
                  ],
                ),
              ),
            SizedBox(
              width: double.maxFinite,
              child: TextField(
                controller: controller,
                maxLines: null,
                minLines: 4,
                autofocus: false,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '可直接修改以下内容',
                  contentPadding: EdgeInsets.all(12),
                ),
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(height: 1.5),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('取消')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            icon: const Icon(Icons.check, size: 18),
            label: Text(confirmLabel),
          ),
        ],
      ),
    );
    controller.dispose();

    final text = result;
    if (text == null || text.isEmpty) return null;
    if (insertToBody) {
      _insertText(text);
      _toast('已插入');
    }
    return text;
  }

  Future<void> _runPolish() async {
    setState(() => _busy = true);
    final svc = ref.read(aiServiceProvider);
    final draft = _draftController.text.trim();
    final out = await svc.polishWriting(draft.isEmpty ? '今天的旅行见闻' : draft);
    if (!mounted) return;
    setState(() => _busy = false);
    if (_checkOk(out)) {
      await _showPreview(title: '润色结果（可修改）', initialText: out);
    } else {
      _handleError(out);
    }
  }

  Future<void> _runSummary() async {
    setState(() => _busy = true);
    final svc = ref.read(aiServiceProvider);
    final today = widget.contentController.text.trim();
    final out = await svc.dailySummary(today.isEmpty ? '（今天还没有正文）' : today);
    if (!mounted) return;
    setState(() => _busy = false);
    if (_checkOk(out)) {
      await _showPreview(title: '每日总结（可修改）', initialText: '\n## 今日总结\n$out');
    } else {
      _handleError(out);
    }
  }

  bool _checkOk(String result) {
    if (result == _notConfigured || result.startsWith(_callFailedPrefix)) return false;
    return true;
  }

  void _handleError(String result) {
    if (result == _notConfigured) {
      _toast('请先在「设置 → AI 设置」填写 API Key');
    } else if (result.startsWith(_callFailedPrefix)) {
      _toast(result.substring(_callFailedPrefix.length));
    }
  }

  Future<void> _runTags() async {
    setState(() => _busy = true);
    final svc = ref.read(aiServiceProvider);
    final content = widget.contentController.text.trim();
    final tags = await svc.suggestTags(content.isEmpty ? '旅行' : content);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _suggestedTags = tags;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: MediaQuery.of(context).size.height * 0.62,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 32, height: 4,
            decoration: BoxDecoration(color: theme.colorScheme.outlineVariant, borderRadius: BorderRadius.circular(2)),
          ),
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(text: '✍️ 写作助手'),
              Tab(text: '📷 描述图片'),
              Tab(text: '🏷️ 智能标签'),
              Tab(text: '📝 每日总结'),
            ],
          ),
          Expanded(
            child: _busy
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildWritingTab(theme),
                      _buildImageDescTab(theme),
                      _buildSmartTagTab(theme),
                      _buildDailySummaryTab(theme),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildWritingTab(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('输入关键词或草稿，AI 将为你润色扩写', style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          Expanded(
            child: TextField(
              controller: _draftController,
              maxLines: null, expands: true,
              decoration: const InputDecoration(
                hintText: '例如：今天去了故宫，天气很好...',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.all(12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: _busy ? null : _runPolish,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('生成预览'),
          )),
        ],
      ),
    );
  }

  /// 从日志**已添加**的照片里挑一张。
  ///
  /// 【不再另开相册选择器】之前让用户从相册重新选图，生成的描述只存在于
  /// 这个弹窗里、随弹窗关闭一起消失，而且那张图可能根本没进日志 —— 等于白做。
  Future<void> _chooseExistingPhoto() async {
    final photos = widget.existingPhotos;
    if (photos.isEmpty) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('选择要描述的照片（共 ${photos.length} 张）',
                  style: Theme.of(ctx).textTheme.titleSmall),
            ),
            Flexible(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                shrinkWrap: true,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemCount: photos.length,
                itemBuilder: (_, i) {
                  final p = photos[i];
                  return GestureDetector(
                    onTap: () => Navigator.pop(ctx, p),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(File(p),
                          fit: BoxFit.cover,
                          cacheWidth: 400,
                          errorBuilder: (_, __, ___) => Container(
                              color: Colors.grey[200],
                              child: const Icon(Icons.broken_image))),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _pickedImagePath = picked;
        _imageDescription = null; // 换图后旧描述不再适用
      });
    }
  }

  Future<void> _runDescribe() async {
    final path = _pickedImagePath;
    if (path == null) return;
    setState(() => _busy = true);
    final svc = ref.read(aiServiceProvider);
    final out = await svc.describeImage(path);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (_checkOk(out)) _imageDescription = out;
    });
    if (!_checkOk(out)) {
      _handleError(out);
      return;
    }
    // 用户确认后才写回：既可作为该照片的说明存库，也可自行决定是否插入正文
    final edited = await _showPreview(
      title: '图片描述',
      initialText: out,
      confirmLabel: '保存描述',
      insertToBody: false,
      photoHint: '第 ${widget.existingPhotos.indexOf(path) + 1} 张照片',
    );
    if (edited == null || !mounted) return;
    widget.onDescribePhoto?.call(path, edited);
    setState(() => _imageDescription = edited);
    _toast('已保存到这张照片');
  }

  /// 把描述同时插入正文（可选的顺手操作）。
  Future<void> _insertDescriptionToBody() async {
    final d = _imageDescription;
    if (d == null) return;
    _insertText(d);
    _toast('已插入正文');
  }

  Widget _buildImageDescTab(ThemeData theme) {
    final hasPhotos = widget.existingPhotos.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 【不要直接 Expanded 包按钮】那样会把按钮垂直拉伸成几百像素高的
          // 巨型色块，看起来完全不像可点的入口 —— 这正是"图片描述用不了"的原因。
          Expanded(
            child: _pickedImagePath == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(hasPhotos ? Icons.photo_library_outlined : Icons.image_not_supported_outlined,
                            size: 46, color: theme.colorScheme.outlineVariant),
                        const SizedBox(height: 12),
                        Text(
                          hasPhotos ? '选择要描述的照片' : '这篇日志还没有照片',
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          hasPhotos
                              ? 'AI 会为它写一句生动的描述'
                              : '请先在上方添加照片，再来生成描述',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.outline),
                        ),
                        const SizedBox(height: 18),
                        if (hasPhotos)
                          FilledButton.tonalIcon(
                            onPressed: _busy ? null : _chooseExistingPhoto,
                            icon: const Icon(Icons.photo_library_outlined),
                            label: Text(
                                '从已添加的 ${widget.existingPhotos.length} 张中选择'),
                          )
                        else
                          OutlinedButton.icon(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.add_photo_alternate_outlined),
                            label: const Text('去添加照片'),
                          ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 190),
                            child: Image.file(File(_pickedImagePath!),
                                fit: BoxFit.cover,
                                // 缩略图只需屏幕宽度的两倍，不必解码整张原图
                                cacheWidth: 900,
                                errorBuilder: (_, __, ___) => const SizedBox(
                                    height: 80,
                                    child: Icon(Icons.broken_image))),
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _chooseExistingPhoto,
                          icon: const Icon(Icons.swap_horiz, size: 18),
                          label: const Text('换一张'),
                        ),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: _busy ? null : _runDescribe,
                          icon: _busy
                              ? const SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.auto_awesome),
                          label: Text(_busy ? '正在识别…' : '生成描述'),
                        ),
                        const SizedBox(height: 12),
                        if (_imageDescription != null) ...[
                          Align(
                              alignment: Alignment.centerLeft,
                              child: Text('描述结果：',
                                  style: theme.textTheme.labelMedium)),
                          const SizedBox(height: 4),
                          Text(_imageDescription!,
                              style: theme.textTheme.bodyMedium),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _busy ? null : _runDescribe,
                                  icon: const Icon(Icons.refresh, size: 18),
                                  label: const Text('重新生成'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FilledButton.tonalIcon(
                                  onPressed: _insertDescriptionToBody,
                                  icon: const Icon(Icons.notes, size: 18),
                                  label: const Text('插入正文'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text('描述已随该照片保存，查看大图时会自动显示',
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline)),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmartTagTab(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('基于日志内容，AI 推荐相关标签', style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: OutlinedButton.icon(
            onPressed: _busy ? null : _runTags,
            icon: const Icon(Icons.sell_outlined),
            label: const Text('分析并推荐'),
          )),
          const SizedBox(height: 16),
          if (_suggestedTags.isNotEmpty) ...[
            Text('点击标签即可插入正文：', style: theme.textTheme.labelMedium),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: _suggestedTags.map((tag) => ActionChip(
              label: Text('#$tag'),
              onPressed: () { _insertText('#$tag '); },
            )).toList()),
            const SizedBox(height: 16),
            if (widget.tripId != null)
              SizedBox(width: double.infinity, child: FilledButton.tonalIcon(
                onPressed: _applyTagsToTrip,
                icon: const Icon(Icons.bookmark_add_outlined),
                label: const Text('全部应用到旅程标签'),
              )),
          ] else
            Expanded(child: Center(child: Text('尚未生成推荐', style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)))),
        ],
      ),
    );
  }

  /// 2.7：把 AI 推荐的标签落库到当前旅程（tags + trip_tags）。
  Future<void> _applyTagsToTrip() async {
    final tripId = widget.tripId;
    if (tripId == null || _suggestedTags.isEmpty) return;
    try {
      await ref.read(databaseProvider).appendTripTags(tripId, _suggestedTags);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已为旅程添加 ${_suggestedTags.length} 个标签')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('应用失败：$e')));
    }
  }

  Widget _buildDailySummaryTab(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const Spacer(),
          const Icon(Icons.summarize_outlined, size: 48, color: Colors.grey),
          const SizedBox(height: 16),
          Text('汇总当天所有正文，生成每日总结', style: theme.textTheme.bodyLarge),
          const SizedBox(height: 8),
          Text('会读取编辑器里已有的内容作为素材', style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
          const Spacer(),
          SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: _busy ? null : _runSummary,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('生成每日总结'),
          )),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
