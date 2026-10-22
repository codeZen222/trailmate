import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/card_style.dart';
import '../../models/mood_type.dart';
import '../../models/profile_model.dart';
import '../../providers/database_provider.dart';
import '../../services/image_storage.dart';
import '../../providers/profile_provider.dart';
import '../../widgets/mood/mood_effect_layer.dart';
import '../../widgets/mood/mood_picker_sheet.dart';
import '../../utils/date_utils.dart' as date_utils;

/// 个人旅行档案编辑页。
class ProfileEditPage extends ConsumerStatefulWidget {
  const ProfileEditPage({super.key});

  @override
  ConsumerState<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends ConsumerState<ProfileEditPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nickname;
  late final TextEditingController _city;
  late final TextEditingController _bio;
  final _bucketInput = TextEditingController();
  final _authorityInput = TextEditingController();

  String? _avatarPath;
  String? _photoPath; // 证件照（档案卡左侧竖版），与圆形头像独立
  List<String> _styles = [];
  List<String> _buckets = [];
  DateTime? _startDate;
  DateTime? _validUntil;
  MoodType? _mood;
  String? _cardStyle;

  List<String> _allTags = const [];

  @override
  void initState() {
    super.initState();
    final p = ref.read(profileProvider);
    _nickname = TextEditingController(text: p?.nickname ?? '');
    _city = TextEditingController(text: p?.homeCity ?? '');
    _bio = TextEditingController(text: p?.bio ?? '');
    _authorityInput.text = p?.issueAuthority ?? '';
    _avatarPath = p?.avatarPath;
    _photoPath = p?.photoPath;
    _styles = List.of(p?.travelStyles ?? const []);
    _buckets = List.of(p?.bucketList ?? const []);
    _startDate = p?.startDate;
    _validUntil = p?.validUntil;
    _mood = p?.mood;
    _cardStyle = p?.cardStyle;
    _loadTags();
  }

  Future<void> _loadTags() async {
    final tags = await ref.read(databaseProvider).getAllTags();
    if (!mounted) return;
    setState(() => _allTags = tags.map((t) => t.name).toList());
  }

  @override
  void dispose() {
    _nickname.dispose();
    _city.dispose();
    _bio.dispose();
    _bucketInput.dispose();
    _authorityInput.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    final p = await ImageStorage.persist(picked.path, folder: ImageStorage.profileDir);
    if (!mounted) return;
    setState(() => _avatarPath = p);
  }

  /// 证件照：竖版裁剪比例更适合档案卡左侧照片位。
  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 900,
      imageQuality: 88,
    );
    if (picked == null || !mounted) return;
    final p = await ImageStorage.persist(picked.path, folder: ImageStorage.profileDir);
    if (!mounted) return;
    setState(() => _photoPath = p);
  }

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? now,
      firstDate: DateTime(1990),
      lastDate: now,
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  /// 有效期限是未来日期，与「旅行起点」（上限为今天）不同，放开到 2099 年。
  Future<void> _pickValidUntil() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _validUntil ?? DateTime(now.year + 10, now.month, now.day),
      firstDate: now,
      lastDate: DateTime(2099),
    );
    if (picked != null) setState(() => _validUntil = picked);
  }

  Future<void> _pickMood() async {
    final r = await MoodPickerSheet.pick(context, initial: _mood);
    if (r == null || !r.confirmed || !mounted) return;
    setState(() => _mood = r.mood);
  }

  void _addBucket() {
    final v = _bucketInput.text.trim();
    if (v.isEmpty) return;
    if (_buckets.contains(v)) {
      _bucketInput.clear();
      return;
    }
    setState(() {
      _buckets = [..._buckets, v];
      _bucketInput.clear();
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    await ref.read(profileProvider.notifier).save(Profile(
          nickname: _nickname.text.trim(),
          avatarPath: _avatarPath,
          photoPath: _photoPath,
          homeCity: _city.text.trim().isEmpty ? null : _city.text.trim(),
          bio: _bio.text.trim().isEmpty ? null : _bio.text.trim(),
          travelStyles: _styles,
          bucketList: _buckets,
          startDate: _startDate,
          mood: _mood,
          cardStyle: _cardStyle,
          issueAuthority: _authorityInput.text.trim().isEmpty
              ? null
              : _authorityInput.text.trim(),
          validUntil: _validUntil,
        ));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('档案已保存')));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑档案'),
        actions: [
          TextButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            // 头像 + 特效预览
            Center(
              child: Stack(
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: cs.surfaceContainerHighest,
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: (_avatarPath == null || _avatarPath!.isEmpty)
                        ? Icon(Icons.person_outline, size: 40, color: cs.outline)
                        : Image.file(File(_avatarPath!), fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                Icon(Icons.broken_image_outlined, color: cs.outline)),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: InkWell(
                      onTap: _pickAvatar,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: cs.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: cs.surface, width: 2),
                        ),
                        child: Icon(Icons.photo_camera_outlined, size: 16, color: cs.onPrimary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: _pickAvatar,
                  icon: const Icon(Icons.account_circle_outlined, size: 16),
                  label: Text(
                      (_avatarPath == null || _avatarPath!.isEmpty) ? '选择头像' : '更换头像'),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: _pickPhoto,
                  icon: Icon(
                    (_photoPath == null || _photoPath!.isEmpty)
                        ? Icons.add_a_photo_outlined
                        : Icons.check_circle_outline,
                    size: 16,
                    color: (_photoPath == null || _photoPath!.isEmpty)
                        ? null
                        : Theme.of(context).colorScheme.primary,
                  ),
                  label: Text(
                      (_photoPath == null || _photoPath!.isEmpty) ? '上传证件照' : '已上传证件照'),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_photoPath != null && _photoPath!.isNotEmpty)
                  Container(
                    width: 42,
                    height: 54,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.file(File(_photoPath!), fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            Icon(Icons.broken_image_outlined, size: 18, color: cs.outline)),
                  ),
                Flexible(
                  child: Text('证件照用于档案卡左侧竖版照片，与圆形头像各自独立',
                      style: theme.textTheme.labelSmall?.copyWith(color: cs.outline)),
                ),
              ],
            ),
            const SizedBox(height: 12),

            _field(theme, '昵称 *', _nickname,
                hint: '卡片上显示的名字',
                maxLength: 16,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '请填写昵称' : null),
            _field(theme, '常驻城市', _city, hint: '例如：成都', maxLength: 12),
            _field(theme, '一句话签名', _bio,
                hint: '例如：把日子过成远方', maxLength: 30, maxLines: 2),

            const SizedBox(height: 18),
            _label(theme, '旅行风格'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _allTags.map((t) {
                final on = _styles.contains(t);
                return FilterChip(
                  label: Text(t),
                  selected: on,
                  showCheckmark: false,
                  selectedColor: cs.primary.withAlpha(45),
                  side: BorderSide(
                      color: on ? cs.primary : cs.outlineVariant,
                      width: on ? 1.4 : 1),
                  onSelected: (v) => setState(() {
                    if (v) {
                      if (_styles.length < 6) _styles = [..._styles, t];
                    } else {
                      _styles = _styles.where((e) => e != t).toList();
                    }
                  }),
                );
              }).toList(),
            ),
            if (_styles.length >= 6)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('最多选 6 个',
                    style: theme.textTheme.labelSmall?.copyWith(color: cs.outline)),
              ),

            const SizedBox(height: 18),
            _label(theme, '心愿目的地'),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: TextField(
                      controller: _bucketInput,
                      maxLength: 20,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _addBucket(),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: '想去还没去的地方',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _addBucket,
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(52, 48), padding: EdgeInsets.zero),
                  child: const Icon(Icons.add),
                ),
              ],
            ),
            if (_buckets.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _buckets
                    .map((b) => InputChip(
                          label: Text(b),
                          avatar: const Icon(Icons.favorite_border, size: 15),
                          onDeleted: () =>
                              setState(() => _buckets = _buckets.where((e) => e != b).toList()),
                        ))
                    .toList(),
              ),
            ],

            const SizedBox(height: 18),
            _label(theme, '旅行起点'),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _pickStartDate,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  border: Border.all(color: cs.outlineVariant),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.event_outlined, size: 18, color: cs.outline),
                    const SizedBox(width: 10),
                    Text(
                      _startDate == null
                          ? '选择你第一次出发的那天'
                          : '${date_utils.formatDateChinese(_startDate!)} · 已是第 ${_daysSince(_startDate)} 天',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const Spacer(),
                    if (_startDate != null)
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() => _startDate = null),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 18),
            _label(theme, '卡片特效'),
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _pickMood,
              child: Container(
                height: 120,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cs.outlineVariant.withAlpha(90)),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    if (_mood != null) MoodEffectLayer(mood: _mood, seed: 21),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: cs.surface.withAlpha(210),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _mood == null ? '点击选择心情特效' : '${_mood!.emoji} ${_mood!.label}',
                          style: theme.textTheme.labelMedium,
                        ),
                      ),
                    ),
                    if (_mood != null)
                      Positioned(
                        right: 4,
                        top: 4,
                        child: IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setState(() => _mood = null),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            _label(theme, '卡片配色'),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: CardStyle.values.map((s) {
                final on = (_cardStyle ?? CardStyle.fallback.key) == s.key;
                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setState(() => _cardStyle = s.key),
                  child: SizedBox(
                    width: 62,
                    child: Column(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          height: 40,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: on ? cs.primary : cs.outlineVariant,
                              width: on ? 2 : 1,
                            ),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                s.bandTop,
                                s.bandTop,
                                s.bodyTop,
                                s.bodyBottom,
                              ],
                              stops: const [0.0, 0.34, 0.34, 1.0],
                            ),
                          ),
                          child: on
                              ? Icon(Icons.check, size: 16, color: Colors.white.withAlpha(230))
                              : null,
                        ),
                        const SizedBox(height: 4),
                        Text(s.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                              color: on ? cs.primary : cs.onSurfaceVariant,
                            )),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 18),
            _label(theme, '证件签发信息'),
            _field(theme, '签发机关', _authorityInput,
                hint: '留空默认「旅行管理局」', maxLength: 12),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _pickValidUntil,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  border: Border.all(color: cs.outlineVariant),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.schedule_outlined, size: 18, color: cs.outline),
                    const SizedBox(width: 10),
                    Text(
                      _validUntil == null
                          ? '有效期限：长期（点击设置）'
                          : '有效期至 ${date_utils.formatDateChinese(_validUntil!)}',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const Spacer(),
                    if (_validUntil != null)
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: '改回长期',
                        onPressed: () => setState(() => _validUntil = null),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  int? _daysSince(DateTime? start) {
    if (start == null) return null;
    final now = DateTime.now();
    final d = DateTime(now.year, now.month, now.day)
        .difference(DateTime(start.year, start.month, start.day))
        .inDays;
    return d + 1;
  }

  Widget _label(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text,
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
      );

  Widget _field(ThemeData theme, String label, TextEditingController ctrl,
      {String? hint, int maxLength = 40, int maxLines = 1, String? Function(String?)? validator}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: ctrl,
        maxLength: maxLength,
        maxLines: maxLines,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
          counterText: '',
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
      ),
    );
  }
}
