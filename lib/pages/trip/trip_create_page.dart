import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../providers/trip_provider.dart';
import '../../services/image_storage.dart';
import '../../providers/database_provider.dart';
import '../../models/trip_model.dart';
import '../../utils/date_utils.dart' as date_utils;

class TripCreatePage extends ConsumerStatefulWidget {
  final int? tripId;

  const TripCreatePage({super.key, this.tripId});

  @override
  ConsumerState<TripCreatePage> createState() => _TripCreatePageState();
}

class _TripCreatePageState extends ConsumerState<TripCreatePage> {
  final _formKey = GlobalKey<FormState>();
  final _destinationController = TextEditingController();
  final _notesController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  String? _coverPath;
  List<int> _selectedTagIds = [];
  List<_TagOption> _availableTags = [];
  bool _isLoading = true;
  bool _saving = false;
  Trip? _editingTrip; // 编辑模式下保留原始旅程，保存时用于更新而非新建

  @override
  void initState() {
    super.initState();
    _loadTags();
    if (widget.tripId != null) {
      _loadTrip(widget.tripId!);
    } else {
      _isLoading = false;
    }
  }

  Future<void> _loadTrip(int tripId) async {
    final db = ref.read(databaseProvider);
    final trip = await db.getTripById(tripId);
    if (trip == null || !mounted) {
      setState(() => _isLoading = false);
      return;
    }
    // 回填表单字段
    _editingTrip = Trip(
      id: trip.id,
      destination: trip.destination,
      coverPath: trip.coverPath,
      startDate: trip.startDate,
      endDate: trip.endDate,
      rating: trip.rating,
      notes: trip.notes,
      isCompleted: trip.isCompleted,
      createdAt: trip.createdAt,
      updatedAt: trip.updatedAt,
    );
    _destinationController.text = trip.destination;
    _notesController.text = trip.notes ?? '';
    _startDate = trip.startDate;
    // 老数据里"没填归期"存成 endDate == startDate，无法与一日行程区分；
    // 以 isCompleted 为准：未完成就把结束日期留空让用户自己补。
    _endDate = trip.isCompleted ? trip.endDate : null;
    _coverPath = trip.coverPath;
    // 回填已选标签
    final tripTags = await db.getTagsByTrip(tripId);
    _selectedTagIds = tripTags.map((t) => t.id).toList();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadTags() async {
    final db = ref.read(databaseProvider);
    final tags = await db.getAllTags();
    _availableTags = tags.map((t) => _TagOption(id: t.id, name: t.name, icon: t.icon ?? '🏷️')).toList();
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _destinationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    // 复制到持久目录，避免 cache 被清导致封面丢失
    final persisted =
        await ImageStorage.persist(picked.path, folder: ImageStorage.coversDir);
    if (!mounted) return;
    setState(() => _coverPath = persisted);
  }

  Future<void> _pickDate(bool isStart) async {
    final now = DateTime.now();
    // 只取年月日：DateTime.now() 带时分秒，直接比较会让「同一天」被误判成
    // 结束日期早于开始日期。
    final startDay = _dayOf(_startDate);
    final endDay = _dayOf(_endDate);
    // 结束日期必须 >= 开始日期：把选择器的 firstDate 直接抬到出发日，
    // 早于开始日期的日子根本选不出来（可以等于），比事后报错更省心。
    final firstDate = isStart ? DateTime(2000) : (startDay ?? DateTime(2000));
    // 结束日期已选时保持它自己的值；未选（进行中）则从出发日开始，
    // 否则会被抬到 2000-01-01 那个极端值上。
    final initial = isStart
        ? (startDay ?? now)
        : (endDay ?? startDay ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    final day = _dayOf(picked)!;
    if (!isStart && startDay != null && day.isBefore(startDay)) {
      // 兜底：万一系统日历绕过了 firstDate 限制，仍然拒绝写入并提示。
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('结束日期不能早于开始日期')),
      );
      return;
    }
    setState(() {
      if (isStart) {
        _startDate = day;
        // 改动开始日后，原本合法的结束日期可能变成早于新的出发日；
        // 与其悄悄清空（用户会以为归期丢了），不如顶到开始日期保持区间有效。
        if (endDay != null && endDay.isBefore(day)) _endDate = day;
      } else {
        _endDate = day;
      }
    });
  }

  /// 归一到当天 00:00，用于纯日期比较与存储。
  static DateTime? _dayOf(DateTime? d) =>
      d == null ? null : DateTime(d.year, d.month, d.day);

  /// 保存旅程。整段包 try/catch：此前任何一步抛异常都会静默中断，
  /// 表现为"点了保存没反应"。
  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    // 只强制开始日期。结束日期可以留空 —— 出发的旅程常常还没定归期，
    // 以前要求两者都填会直接挡住保存，体验很差。
    if (_startDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择开始日期')),
      );
      return;
    }

    // endDate 保持真实值：没填时等同于出发日。
    // 「进行中」由 isCompleted 表达，不靠日期去猜 —— 否则当天往返的一日行程会被误判。
    final end = _endDate ?? _startDate!;
    final completed = _endDate != null;

    // 兜底校验（编辑老数据时尤其重要）：库里可能存着结束早于开始的脏数据，
    // 回填后用户没碰日期就直接保存的话，会把非法区间原样写回去。
    if (end.isBefore(_startDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('结束日期不能早于开始日期')),
      );
      return;
    }

    final notes = _notesController.text.trim().isEmpty ? null : _notesController.text.trim();
    final isEdit = widget.tripId != null && _editingTrip != null;
    setState(() => _saving = true);

    try {
      if (isEdit) {
        // 编辑：更新原记录，避免重复新建
        await updateTrip(
          ref,
          _editingTrip!.copyWith(
            destination: _destinationController.text.trim(),
            coverPath: _coverPath,
            startDate: _startDate!,
            endDate: end,
            isCompleted: completed,
            notes: notes,
          ),
        );
        await ref.read(databaseProvider).setTripTags(widget.tripId!, _selectedTagIds);
      } else {
        await createTrip(ref,
          destination: _destinationController.text.trim(),
          coverPath: _coverPath,
          startDate: _startDate!,
          endDate: end,
          notes: notes,
          tagIds: _selectedTagIds,
          isCompleted: completed,
        );
      }

      // 旅程详情同样是 FutureProvider，需失效后才能看到新数据
      if (isEdit) ref.invalidate(tripByIdProvider(widget.tripId!));

      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_endDate == null && !isEdit
                ? '已创建（未定归期，标记为进行中）'
                : isEdit
                    ? '旅程已更新'
                    : '旅程已创建')),
      );
      Navigator.pop(context);
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _saving = false);
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('保存失败'),
          content: SingleChildScrollView(
            child: SelectableText('$e\n\n----\n$st',
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('知道了')),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.tripId != null ? '编辑旅程' : '创建旅程'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('保存'),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 封面图
                    GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        height: 180,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: _coverPath != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(15),
                                child: Image.file(
                                  File(_coverPath!),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _buildPlaceholder(colorScheme),
                                ),
                              )
                            : _buildPlaceholder(colorScheme),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 目的地
                    TextFormField(
                      controller: _destinationController,
                      decoration: const InputDecoration(
                        labelText: '目的地',
                        hintText: '例如：云南大理',
                        prefixIcon: Icon(Icons.luggage_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty ? '请输入目的地' : null,
                    ),
                    const SizedBox(height: 16),

                    // 日期
                    Row(
                      children: [
                        Expanded(
                          child: _DatePickerButton(
                            label: '开始日期',
                            date: _startDate,
                            onTap: () => _pickDate(true),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _DatePickerButton(
                            label: '结束日期（可留空）',
                            date: _endDate,
                            onTap: () => _pickDate(false),
                            // 已选过的可以清空，否则用户误选后没法反悔
                            onClear: _endDate == null
                                ? null
                                : () => setState(() => _endDate = null),
                          ),
                        ),
                      ],
                    ),
                    if (_startDate != null && _endDate == null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          children: [
                            Icon(Icons.timelapse,
                                size: 14, color: theme.colorScheme.primary),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text('未定归期，将标记为「进行中」',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.primary)),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 20),

                    // 标签
                    Text('标签', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _availableTags.map((tag) {
                        final selected = _selectedTagIds.contains(tag.id);
                        return FilterChip(
                          label: Text('${tag.icon} ${tag.name}'),
                          selected: selected,
                          onSelected: (val) {
                            setState(() {
                              if (val) {
                                _selectedTagIds.add(tag.id);
                              } else {
                                _selectedTagIds.remove(tag.id);
                              }
                            });
                          },
                          avatar: selected
                              ? const Icon(Icons.check, size: 16)
                              : null,
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),

                    // 备注
                    TextField(
                      controller: _notesController,
                      decoration: const InputDecoration(
                        labelText: '备注（可选）',
                        hintText: '简短记录一下这次旅行的主题...',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 32),

                    // 保存按钮
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _save,
                        child: Text(widget.tripId != null ? '保存修改' : '创建旅程'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildPlaceholder(ColorScheme colorScheme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.add_photo_alternate_outlined, size: 48, color: colorScheme.outline),
        const SizedBox(height: 8),
        Text('点击选择封面图', style: TextStyle(color: colorScheme.outline)),
      ],
    );
  }
}

class _DatePickerButton extends StatelessWidget {
  final String label;
  final DateTime? date;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _DatePickerButton({
    required this.label,
    required this.date,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outline.withAlpha(80)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
            )),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.calendar_today, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    date != null ? date_utils.formatDate(date!) : '未定',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      // 空值时给出"这是可选的、不是漏填"的视觉暗示
                      color: date == null ? theme.colorScheme.outline : null,
                      fontStyle: date == null ? FontStyle.italic : null,
                    ),
                  ),
                ),
                if (onClear != null)
                  GestureDetector(
                    onTap: onClear,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(Icons.cancel_outlined,
                          size: 17, color: theme.colorScheme.outline),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TagOption {
  final int id;
  final String name;
  final String icon;
  _TagOption({required this.id, required this.name, required this.icon});
}