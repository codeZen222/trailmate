import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:drift/drift.dart' show Value;
import '../../providers/database_provider.dart';
import '../../providers/log_provider.dart';
import '../../database/app_database.dart' as db;
import '../../services/location_service.dart';
import '../../services/image_storage.dart';
import '../../services/weather_service.dart';
import '../../models/mood_type.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/mood/mood_effect_layer.dart';
import '../../widgets/mood/mood_picker_sheet.dart';
import '../../utils/date_utils.dart' as date_utils;
import 'widgets/ai_assist_bottom_sheet.dart';

final _locationServiceProvider = Provider<LocationService>((ref) => LocationService());

class LogEditorPage extends ConsumerStatefulWidget {
  final int tripId;
  final int? logId;
  final DateTime? selectedDate;

  const LogEditorPage({
    super.key,
    required this.tripId,
    this.logId,
    this.selectedDate,
  });

  @override
  ConsumerState<LogEditorPage> createState() => _LogEditorPageState();
}

class _LogEditorPageState extends ConsumerState<LogEditorPage> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  String? _weather;
  int? _rating;
  List<String> _imagePaths = [];

  /// 待写入的图片 AI 描述（path -> description）。
  /// 新建日志时图片尚未入库，无法直接 UPDATE，所以先暂存到这里，保存时一并落库。
  final Map<String, String> _descByPath = {};

  /// AI 生成并确认后的描述：已入库的立即写库，未入库的暂存到保存时处理。
  void _onPhotoDescribed(String path, String description) {
    _descByPath[path] = description;
    if (widget.logId != null) {
      // 编辑已有日志：图片记录已存在，可直接更新
      ref
          .read(databaseProvider)
          .setImageDescriptionByPath(path, description)
          .catchError((e) {
        debugPrint('写入图片描述失败: $e');
        return 0;
      });
      _descByPath.remove(path);
    }
  }

  /// 批量导入进行中：复制到持久目录需要时间，期间给出可见反馈。
  bool _importing = false;
  bool _isLoading = true;
  bool _saving = false;
  String? _loadError;

  // GPS 定位状态
  double? _latitude;
  double? _longitude;
  String? _cityName;
  String? _placeName;
  bool _locating = false;

  // 心情标签（带粒子特效）
  MoodType? _mood;

  static const List<String> weatherOptions = ['☀️ 晴', '⛅ 多云', '🌧️ 雨', '❄️ 雪'];

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.selectedDate ?? DateTime.now();
    if (widget.logId != null) {
      _loadLog();
    } else {
      _isLoading = false;
    }
  }

  Future<void> _loadLog() async {
    final database = ref.read(databaseProvider);
    try {
      final log = await database.getLogById(widget.logId!);
      if (log == null) {
        if (!mounted) return;
        setState(() {
          _loadError = '数据库里找不到这篇日志（id=${widget.logId}）';
          _isLoading = false;
        });
        return;
      }
      _titleController.text = log.title ?? '';
      _contentController.text = log.content;
      _selectedDate = log.date;
      _weather = log.weather;
      _mood = MoodType.fromKey(log.moodTag);
      _rating = log.rating;

      final images = await database.getImagesByLogOrdered(widget.logId!);
      _imagePaths = images.map((img) => img.filePath).toList();
      // 载入已有 AI 描述，避免每次编辑都要重新生成
      _descByPath.addEntries(images
          .where((i) => (i.aiDescription ?? '').trim().isNotEmpty)
          .map((i) => MapEntry(i.filePath, i.aiDescription!.trim())));

      final loc = await database.getLocationByLog(widget.logId!);
      if (loc != null) {
        _latitude = loc.latitude;
        _longitude = loc.longitude;
        _cityName = loc.cityName;
        _placeName = loc.placeName;
      }
      if (!mounted) return;
      setState(() => _isLoading = false);
    } catch (e, st) {
      // 不静默失败：把原因显示出来，否则用户只会看到"点了没反应"
      if (!mounted) return;
      setState(() {
        _loadError = '$e\n\n----\n$st';
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  /// 单张添加（拍照入口用）。
  Future<void> _addPicked(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source);
    if (picked == null || !mounted) return;
    await _persistAndAdd([picked.path]);
  }

  /// 批量挑选并入库。
  ///
  /// 【为什么单独写一个】image_picker 给的可能是缓存目录里的临时路径，
  /// 重装 App 或系统清理后文件就没了（之前照片"莫名消失"就是这个原因）。
  /// 所以每张都必须先复制到应用私有目录再存路径。
  Future<void> _persistAndAdd(List<String> rawPaths) async {
    if (rawPaths.isEmpty) return;
    setState(() => _importing = true);
    try {
      final added = <String>[];
      for (final p in rawPaths) {
        final persisted =
            await ImageStorage.persist(p, folder: ImageStorage.photosDir);
        added.add(persisted);
      }
      if (!mounted) return;
      setState(() {
        _imagePaths.addAll(added);
        _importing = false;
      });
      if (added.length > 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已添加 ${added.length} 张照片')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _importing = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('添加照片失败：$e')));
    }
  }

  /// 从相册一次选多张。
  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(imageQuality: 90);
    if (picked.isEmpty || !mounted) return;
    // 单次上限，避免一次塞进上百张把内存和后续海报渲染拖垮
    const maxBatch = 30;
    var paths = picked.map((f) => f.path).toList();
    if (paths.length > maxBatch) paths = paths.sublist(0, maxBatch);
    await _persistAndAdd(paths);
    if (picked.length > maxBatch && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('一次最多导入 $maxBatch 张，其余已忽略')),
      );
    }
  }

  Future<void> _takePhoto() => _addPicked(ImageSource.camera);

  void _showImagePicker() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('拍照'),
              onTap: () {
                Navigator.pop(ctx);
                _takePhoto();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从相册选择'),
              subtitle: const Text('可长按/勾选多张，一次全部添加'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImages();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showWeatherPicker() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: weatherOptions.map((w) => ListTile(
            leading: Text(w.split(' ')[0]),
            title: Text(w.split(' ').sublist(1).join(' ')),
            trailing: _weather == w ? const Icon(Icons.check) : null,
            onTap: () {
              setState(() => _weather = w);
              Navigator.pop(ctx);
            },
          )).toList(),
        ),
      ),
    );
  }

  /// 选择心情标签（带粒子特效预览）。
  Future<void> _pickMood() async {
    final result = await MoodPickerSheet.pick(context, initial: _mood);
    if (result == null || !result.confirmed || !mounted) return;
    setState(() => _mood = result.mood);
    if (result.mood != null && !ref.read(effectsProvider)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('提示：你已关闭「日志特效」，心情标签仍会记录但无动画')),
      );
    }
  }

  /// GPS 单次定位：获取坐标 + 反查城市/街道，结果存入内存态，保存时落库。
  /// 详细位置文案：「烟台市 · 芝罘区 · 月亮湾」。
  ///
  /// 【为什么要拼】逆地理编码其实已经返回了省/市/区/街道/POI，
  /// 但界面只显示了城市名，"月亮湾"这种真正有用的信息被丢掉了。
  String _locationLabel() {
    final parts = <String>[];
    final city = _cityName?.trim();
    if (city != null && city.isNotEmpty) parts.add(city);

    // placeName 存的是完整地址串，需要拆掉与 cityName 重复的前缀再取末段
    final raw = _placeName?.trim();
    if (raw != null && raw.isNotEmpty) {
      var rest = raw;
      if (city != null && rest.startsWith(city)) {
        rest = rest.substring(city.length);
      }
      // 按行政区划层级切开，丢掉空段
      final segs = rest
          .split(RegExp(r'(?<=[省市区县])|[\s,，、]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      for (final s in segs) {
        if (!parts.contains(s)) parts.add(s);
      }
    }
    if (parts.isEmpty) return '已定位';
    return parts.join(' · ');
  }

  Future<void> _captureLocation() async {
    setState(() => _locating = true);
    final svc = ref.read(_locationServiceProvider);
    final pos = await svc.getCurrentPosition();
    if (!mounted) return;
    if (pos == null) {
      setState(() => _locating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法获取定位，请检查定位权限是否开启')),
      );
      return;
    }
    final city = await svc.getCityName(pos.latitude, pos.longitude);
    final street = await svc.getAddress(pos.latitude, pos.longitude);
    final admin = await svc.getAdminDivisions(pos.latitude, pos.longitude);
    if (!mounted) return;
    setState(() {
      _latitude = pos.latitude;
      _longitude = pos.longitude;
      _cityName = city;
      // 区名并入 placeName，界面按「市 · 区 · 地点」展示
      _placeName = [
        if ((admin.district ?? '').isNotEmpty) admin.district,
        if ((street ?? '').isNotEmpty && street != admin.district) street,
      ].join(' ');
    });

    // 定位成功后自动获取实时天气（若已配置天气接口）
    String? weatherHint;
    final wf = ref.read(weatherFetcherProvider);
    final (ok, _, result) = await wf.fetchCurrent(pos.latitude, pos.longitude);
    if (ok && result != null) {
      weatherHint = '${result.text} ${result.tempC}°';
      if (mounted) setState(() => _weather = result.display);
    }

    if (!mounted) return;
    setState(() => _locating = false);
    final parts = <String>[
      if (city != null) '已定位到 $city',
      if (weatherHint != null) '天气：$weatherHint'
    ];
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(parts.isEmpty ? '已记录当前位置' : parts.join('，'))),
    );
  }

  /// 加载失败时把原因直接显示在屏幕上，便于用户截图反馈。
  Widget _errorView() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 30),
          const SizedBox(height: 10),
          Text('日志加载失败',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Expanded(
            child: SingleChildScrollView(
              child: SelectableText(
                _loadError ?? '',
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace', height: 1.5),
              ),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => setState(() => _loadError = null),
              child: const Text('仍然新建/编辑'),
            ),
          ),
        ],
      ),
    );
  }

  /// 保存日志。整段包 try/catch：此前任何一步抛异常都会静默中断，
  /// 表现为"点了保存没反应"，用户完全不知道失败。
  Future<void> _save() async {
    if (_saving) return;
    if (_contentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入日志内容')),
      );
      return;
    }

    setState(() => _saving = true);
    final isEdit = widget.logId != null;
    final database = ref.read(databaseProvider);
    try {
      int savedLogId;
      if (isEdit) {
        final changed = await database.updateLog(widget.logId!, db.LogsCompanion(
          tripId: Value(widget.tripId),
          date: Value(_selectedDate),
          title: Value(_titleController.text.trim().isEmpty ? null : _titleController.text.trim()),
          content: Value(_contentController.text.trim()),
          weather: Value(_weather),
          moodTag: Value(_mood?.key),
          rating: Value(_rating),
          updatedAt: Value(DateTime.now()),
        ));
        // 没匹配到行 = 什么都没保存，必须报错而不是假装成功
        if (changed == 0) {
          throw StateError('未找到要更新的日志（id=${widget.logId}），本次未保存任何内容');
        }
        savedLogId = widget.logId!;
      } else {
        savedLogId = await database.insertLog(db.LogsCompanion(
          tripId: Value(widget.tripId),
          date: Value(_selectedDate),
          title: Value(_titleController.text.trim().isEmpty ? null : _titleController.text.trim()),
          content: Value(_contentController.text.trim()),
          weather: Value(_weather),
          moodTag: Value(_mood?.key),
          rating: Value(_rating),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ));
      }

      // 图片同步放在分支外：编辑时新增/删除的照片此前会被静默丢弃
      await database.syncLogImages(savedLogId, _imagePaths);

      // 暂存的 AI 描述落库（新建日志时图片刚插入，只能此刻写入）
      for (final e in _descByPath.entries) {
        await database.setImageDescriptionByPath(e.key, e.value);
      }
      _descByPath.clear();

      // GPS 定位落库（仅当本次会话获取到了坐标）
      if (_latitude != null && _longitude != null) {
        await database.upsertLocationForLog(
          logId: savedLogId,
          latitude: _latitude!,
          longitude: _longitude!,
          cityName: _cityName,
          placeName: _placeName,
        );
      }

      // 详情页用的是 FutureProvider（有缓存），不失效就会显示旧内容
      ref.invalidate(logByIdProvider(savedLogId));

      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isEdit ? '日志已更新' : '日志已保存')),
      );
      Navigator.pop(context);
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _saving = false);
      // 把真实原因显示出来，不再静默失败
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('保存失败'),
          content: SingleChildScrollView(
            child: Text('$e\n\n----\n$st',
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
        title: Text(widget.logId != null ? '编辑日志' : '写日志'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ],
      ),
      body: _loadError != null
          ? _errorView()
          : _isLoading
              ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today, size: 16, color: colorScheme.outline),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _selectedDate,
                            firstDate: DateTime(2000),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) setState(() => _selectedDate = picked);
                        },
                        icon: const Icon(Icons.edit_calendar, size: 16),
                        label: Text(date_utils.formatDateChinese(_selectedDate)),
                      ),
                      const Spacer(),
                      if (_weather != null)
                        Text(_weather!, style: const TextStyle(fontSize: 16)),
                    ],
                  ),
                ),
                if (_cityName != null || _latitude != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Chip(
                        avatar: Icon(Icons.place, size: 16, color: colorScheme.onSecondaryContainer),
                        label: ConstrainedBox(
                          constraints: BoxConstraints(
                              maxWidth: MediaQuery.sizeOf(context).width - 150),
                          child: Text(_locationLabel(),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        deleteIcon: const Icon(Icons.close, size: 18),
                        onDeleted: () => setState(() {
                          _latitude = null;
                          _longitude = null;
                          _cityName = null;
                          _placeName = null;
                        }),
                      ),
                    ),
                  ),
                if (_imagePaths.isNotEmpty)
                  Container(
                    height: 80,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _imagePaths.length + 1,
                      itemBuilder: (context, index) {
                        if (index == _imagePaths.length) {
                          return _AddImageButton(onTap: _showImagePicker);
                        }
                        return _ImageThumbnail(
                          path: _imagePaths[index],
                          onRemove: () => setState(() => _imagePaths.removeAt(index)),
                        );
                      },
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: OutlinedButton.icon(
                      onPressed: _importing ? null : _showImagePicker,
                      icon: _importing
                          ? const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.add_photo_alternate_outlined, size: 18),
                      label: Text(_importing ? '正在导入…' : '添加图片'),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      hintText: '标题（可选）',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                    ),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Stack(
                      children: [
                        // 写作区背景实时预览所选心情特效
                        if (_mood != null && ref.watch(effectsActiveProvider))
                          MoodEffectLayer(mood: _mood, seed: _mood!.key.length * 13 + 5),
                        Positioned.fill(
                          child: TextField(
                            controller: _contentController,
                            decoration: const InputDecoration(
                              hintText: '开始写今天的旅行故事...\n\n支持 Markdown 格式',
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(vertical: 12),
                            ),
                            maxLines: null,
                            expands: true,
                            textAlignVertical: TextAlignVertical.top,
                            style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(15),
                blurRadius: 4,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: _showWeatherPicker,
                icon: Text(_weather ?? '🌤️', style: const TextStyle(fontSize: 20)),
                tooltip: '天气',
              ),
              IconButton(
                onPressed: _pickMood,
                icon: _mood == null
                    ? Icon(Icons.mood_outlined,
                        color: _mood == null ? colorScheme.outline : null)
                    : Text(_mood!.emoji, style: const TextStyle(fontSize: 20)),
                tooltip: _mood?.label ?? '心情特效',
              ),
              IconButton(
                onPressed: _locating ? null : _captureLocation,
                icon: _locating
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(
                        _cityName != null ? Icons.location_on : Icons.location_on_outlined,
                        color: _cityName != null ? colorScheme.primary : null,
                      ),
                tooltip: _cityName ?? '定位',
              ),
              IconButton(
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (ctx) => AiAssistBottomSheet(
                      contentController: _contentController,
                      tripId: widget.tripId,
                      existingPhotos: _imagePaths,
                      onDescribePhoto: _onPhotoDescribed,
                    ),
                  );
                },
                icon: Icon(Icons.auto_awesome_outlined, color: colorScheme.primary),
                tooltip: 'AI 辅助',
              ),
              const Spacer(),
              if (_rating != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(5, (i) => IconButton(
                    onPressed: () => setState(() => _rating = i + 1),
                    icon: Icon(
                      i < _rating! ? Icons.star : Icons.star_border,
                      size: 20,
                      color: Colors.amber,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  )),
                )
              else
                IconButton(
                  onPressed: () => setState(() => _rating = 5),
                  icon: const Icon(Icons.star_border, size: 20),
                  tooltip: '心情评分',
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageThumbnail extends StatelessWidget {
  final String path;
  final VoidCallback onRemove;

  const _ImageThumbnail({required this.path, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(
              File(path),
              width: 64,
              height: 64,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 64,
                height: 64,
                color: Colors.grey[200],
                child: const Icon(Icons.broken_image),
              ),
            ),
          ),
          Positioned(
            top: -4,
            right: -4,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddImageButton extends StatelessWidget {
  final VoidCallback onTap;

  const _AddImageButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outline.withAlpha(80)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          Icons.add,
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }
}