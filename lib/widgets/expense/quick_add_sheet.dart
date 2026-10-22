import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/expense_model.dart';
import '../../providers/expense_provider.dart';
import '../../providers/trip_provider.dart';
import '../../utils/date_utils.dart' as date_utils;

/// 快速记账面板。
/// 保存后**不关闭**，只清金额、保留分类/旅程/日期——旅途中连记几笔是高频场景。
class QuickAddSheet extends ConsumerStatefulWidget {
  const QuickAddSheet({super.key, this.initialTripId});

  final int? initialTripId;

  static Future<void> show(BuildContext context, {int? tripId}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => QuickAddSheet(initialTripId: tripId),
    );
  }

  @override
  ConsumerState<QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends ConsumerState<QuickAddSheet> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  ExpenseCategory _category = ExpenseCategory.food;
  DateTime _date = DateTime.now();
  int? _tripId;
  bool _tripTouched = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  /// 默认旅程：优先「正在进行」的那段，否则取开始日期最新的那段。
  /// 【不能取 trips.first】——tripListProvider 是按日期**正序**的，
  /// first 会是最早的旅程。
  int? _resolveTripId(List<TripOption> trips) {
    if (_tripTouched && _tripId != null) return _tripId;
    if (widget.initialTripId != null) return widget.initialTripId;
    if (trips.isEmpty) return null;
    final ongoing = trips.where((t) => t.isOngoing).toList()
      ..sort((a, b) => b.startDate.compareTo(a.startDate));
    if (ongoing.isNotEmpty) return ongoing.first.id;
    return trips.reduce((a, b) => a.startDate.isAfter(b.startDate) ? a : b).id;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save({required bool keepOpen}) async {
    final cents = Money.parseInput(_amountController.text);
    if (cents == null || cents <= 0) {
      setState(() => _error = '请输入大于 0 的金额');
      return;
    }
    if (_tripId == null) {
      setState(() => _error = '请选择所属旅程');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await createExpense(
        ref,
        tripId: _tripId!,
        category: _category,
        amountCents: cents,
        date: _date,
        note: _noteController.text,
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _amountController.clear();
        _noteController.clear();
        _error = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已记一笔：${_category.emoji} ${_category.label} ${Money.format(cents)}')),
      );
      if (!keepOpen) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '保存失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tripsAsync = ref.watch(tripListProvider);
    final options = (tripsAsync.valueOrNull ?? [])
        .map((t) => TripOption(t.id, t.destination,
            startDate: t.startDate, endDate: t.endDate))
        .toList()
      // 记账时想选的多是最近/进行中的旅程，选择列表按日期倒序更顺手；
      // 与 provider 的展示顺序（正序）刻意不同。
      ..sort((a, b) => b.startDate.compareTo(a.startDate));
    _tripId ??= _resolveTripId(options);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 32, height: 4,
                  decoration: BoxDecoration(
                      color: cs.outlineVariant, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 14),
              Text('记一笔', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),

              // 金额
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Text('¥',
                        style: theme.textTheme.headlineMedium
                            ?.copyWith(color: cs.outline, fontWeight: FontWeight.w300)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _amountController,
                        autofocus: true,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                        textAlign: TextAlign.left,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: '0.00',
                          hintStyle: TextStyle(color: Color(0xFFBDBDBD)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 分类
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ExpenseCategory.all.map((c) {
                  final on = _category == c;
                  return ChoiceChip(
                    selected: on,
                    showCheckmark: false,
                    avatar: Text(c.emoji, style: const TextStyle(fontSize: 15)),
                    label: Text(c.label),
                    selectedColor: c.color.withAlpha(46),
                    side: BorderSide(color: on ? c.color : cs.outlineVariant, width: on ? 1.6 : 1),
                    labelStyle: TextStyle(
                        fontSize: 12.5, fontWeight: on ? FontWeight.w700 : FontWeight.w500),
                    onSelected: (_) => setState(() => _category = c),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),

              // 旅程 + 日期
              Row(
                children: [
                  Expanded(
                    child: _picker(
                      theme,
                      icon: Icons.place_outlined,
                      label: options.isEmpty
                          ? '还没有旅程'
                          : (options.firstWhere((o) => o.id == _tripId, orElse: () => options.first).name),
                      onTap: options.isEmpty
                          ? null
                          : () async {
                              final picked = await showTripPicker(context, options, _tripId);
                              if (picked != null) {
                                setState(() {
                                  _tripId = picked;
                                  _tripTouched = true;
                                });
                              }
                            },
                    ),
                  ),
                  const SizedBox(width: 10),
                  _picker(
                    theme,
                    icon: Icons.event_outlined,
                    label: date_utils.formatShortDate(_date),
                    onTap: _pickDate,
                  ),
                ],
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _noteController,
                maxLength: 30,
                decoration: const InputDecoration(
                  counterText: '',
                  isDense: true,
                  hintText: '备注（可选）：如 龙门石窟门票',
                  prefixIcon: Icon(Icons.edit_outlined, size: 18),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(),
                ),
              ),

              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!,
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.error)),
                ),

              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => _save(keepOpen: false),
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(46)),
                      child: const Text('记一笔并关闭'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : () => _save(keepOpen: true),
                      icon: _saving
                          ? const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.add),
                      label: const Text('记一笔'),
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(46)),
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

  Widget _picker(ThemeData theme,
      {required IconData icon, required String label, VoidCallback? onTap}) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: cs.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: cs.outline),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium),
            ),
            Icon(Icons.expand_more, size: 18, color: cs.outline),
          ],
        ),
      ),
    );
  }
}

class TripOption {
  const TripOption(this.id, this.name, {required this.startDate, required this.endDate});
  final int id;
  final String name;
  final DateTime startDate;
  final DateTime endDate;

  /// 今天是否正处在这段旅程期间。
  bool get isOngoing {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final s = DateTime(startDate.year, startDate.month, startDate.day);
    final e = DateTime(endDate.year, endDate.month, endDate.day);
    return !today.isBefore(s) && !today.isAfter(e);
  }
}

Future<int?> showTripPicker(
    BuildContext context, List<TripOption> options, int? current) {
  return showModalBottomSheet<int>(
    context: context,
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text('选择旅程', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          for (final o in options)
            ListTile(
              leading: Icon(o.id == current ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 20),
              title: Text(o.name),
              onTap: () => Navigator.pop(ctx, o.id),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
