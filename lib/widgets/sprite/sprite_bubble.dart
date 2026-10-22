import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/sprite_form.dart';
import '../../models/trip_model.dart';
import '../../providers/database_provider.dart';
import '../../providers/expense_provider.dart';
import '../../providers/sprite_provider.dart';
import '../../providers/trip_provider.dart';
import '../../services/ai_service.dart';
import '../../services/expense_intent.dart';
import 'travel_sprite.dart';

/// 精灵的迷你对话窗。与全屏 AI 页共用 `ai_chat_sessions` 的第一条会话，
/// 所以不会分裂成两套记忆。
class SpriteBubble extends ConsumerStatefulWidget {
  const SpriteBubble({
    super.key,
    required this.form,
    this.onOpenFullChat,
    this.onDragStart,
    this.onDragUpdate,
  });

  final SpriteForm form;
  final VoidCallback? onOpenFullChat;

  /// 顶部标题栏拖拽：让整张小窗可以移动。
  final void Function(Offset globalPosition)? onDragStart;
  final void Function(Offset delta)? onDragUpdate;

  @override
  ConsumerState<SpriteBubble> createState() => _SpriteBubbleState();
}

class _Msg {
  _Msg(this.role, this.text);
  final String role; // user / assistant
  final String text;
}

class _SpriteBubbleState extends ConsumerState<SpriteBubble> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  List<_Msg> _messages = [];
  bool _busy = false;
  SpriteMood _mood = SpriteMood.idle;
  CancelToken? _cancel;

  /// 待确认的记账意图（解析出来后先给用户看，确认才入账）。
  ExpenseIntent? _pending;
  int? _pendingTripId;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _cancel?.cancel();
    super.dispose();
  }

  /// 读取共享会话的第一条（最新会话）。
  Future<void> _loadSession() async {
    final raw = await ref.read(databaseProvider).getSetting(sessionsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw);
      if (list is! List || list.isEmpty) return;
      final first = Map<String, dynamic>.from(list.first as Map);
      final msgs = ((first['messages'] as List?) ?? [])
          .map((e) {
            final m = Map<String, dynamic>.from(e as Map);
            return _Msg(m['role'] as String? ?? 'user',
                m['text'] as String? ?? '');
          })
          .where((m) => m.text.isNotEmpty)
          .toList();
      if (msgs.isNotEmpty && mounted) {
        setState(() => _messages = msgs);
        _jumpBottom();
      }
    } catch (_) {
      // 解析失败就当空会话，不影响使用
    }
  }

  /// 写回共享会话：更新第一条的 messages 与 updated。
  Future<void> _saveSession() async {
    final db = ref.read(databaseProvider);
    final raw = await db.getSetting(sessionsKey);
    List<dynamic> sessions = [];
    try {
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) sessions = decoded;
      }
    } catch (_) {
      sessions = [];
    }
    if (sessions.isEmpty) {
      sessions.add({
        'id': 'sprite-${DateTime.now().millisecondsSinceEpoch}',
        'updated': DateTime.now().toIso8601String(),
        'messages': <dynamic>[],
      });
    }
    final head = Map<String, dynamic>.from(sessions.first as Map);
    head['updated'] = DateTime.now().toIso8601String();
    head['messages'] = _messages
        .map((m) => {'role': m.role, 'text': m.text})
        .toList();
    sessions[0] = head;
    await db.setSetting(sessionsKey, jsonEncode(sessions));
  }

  void _jumpBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  /// 快捷短语：填入输入框后立即发送。
  void _sendPreset(String text) {
    _input.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _send();
  }

  /// 【临时诊断】输出输入框的真实内部状态。
  /// composing 是输入法未上屏的部分，clear() 不会清除它 —— 这正是怀疑对象。
  void _dbg(String tag, TextEditingValue v) {
    debugPrint('[SPRITE-IN $tag]'
        ' text="${v.text}"'
        ' composing=${v.composing.start}..${v.composing.end}'
        ' sel=${v.selection.baseOffset}..${v.selection.extentOffset}'
        ' busy=$_busy');
  }

  /// 把输入框彻底清空。
  ///
  /// 【为什么不用 _input.clear()】clear() 只重置 text/selection，
  /// **不会清 composing region** —— 也就是中文输入法里那段还没上屏的拼音候选。
  /// 你打字时看到的是「你好」，实际 controller 里可能还挂着一段未确认的 composing；
  /// 一旦发送时机与输入法合成时机交错，就会出现「删掉了但又自己冒出来」的现象。
  /// 这里显式赋一个完全空的 value，把 composing 一起抹掉。
  void _clearInput() {
    _input.value = const TextEditingValue(
      text: '',
      selection: TextSelection.collapsed(offset: 0),
      composing: TextRange.empty,
    );
  }

  /// 发送一条消息。
  ///
  /// 【修掉的两个问题】
  ///   ① 原先 `_input.clear()` 排在 `_busy` 判断之后：流式回复期间按回车会直接
  ///      return，文字既没清掉也没发出去；
  ///   ② 原先用 clear() 无法清除输入法未上屏的 composing 文本，导致删除后回弹。
  /// 现在先无条件彻底清空，再判断是否可以发送。
  Future<void> _send() async {
    final text = _input.text.trim();
    _dbg('before-clear', _input.value);
    _clearInput();
    _dbg('after-clear', _input.value);
    if (text.isEmpty || _busy) return;

    setState(() {
      _messages.add(_Msg('user', text));
      _busy = true;
      _mood = SpriteMood.thinking;
    });
    _jumpBottom();

    // 本地记账解析：命中就生成确认卡，不打扰 AI
    final intent = ExpenseIntentParser.tryParse(text);
    if (intent != null) {
      final trips = ref.read(tripListProvider).valueOrNull ?? const [];
      setState(() {
        _pending = intent;
        _pendingTripId =
            trips.isEmpty ? null : trips.last.id; // 正序最后一个是最近旅程
        _busy = false;
        _mood = SpriteMood.happy;
        _messages.add(_Msg(
            'assistant',
            '听上去是一笔消费：${intent.category.emoji} ${intent.category.label} '
                '${intent.amountText}。确认一下就帮你记上 👇'));
      });
      await _saveSession();
      _resetMoodLater();
      return;
    }

    await _askAi(text);
  }

  Future<void> _askAi(String text) async {
    setState(() {
      _busy = true;
      _mood = SpriteMood.thinking;
    });
    final history = _messages
        .map((m) => {'role': m.role, 'content': m.text})
        .toList();
    final assistant = _Msg('assistant', '');
    setState(() => _messages.add(assistant));

    final idx = _messages.length - 1;
    final buffer = StringBuffer();
    _cancel = CancelToken();
    String result;
    try {
      result = await ref.read(aiServiceProvider).chatStream(
        history,
        cancelToken: _cancel,
        onChunk: (delta) {
          if (!mounted) return;
          buffer.write(delta);
          setState(() => _messages[idx] = _Msg('assistant', buffer.toString()));
          _mood = SpriteMood.speaking;
          _jumpBottom();
        },
      );
    } catch (e) {
      result = '__CALL_FAILED__:$e';
    }
    if (!mounted) return;
    _cancel = null;

    final failed = result.startsWith('__');
    var reply = buffer.isNotEmpty ? buffer.toString() : result;
    if (failed) {
      reply = result.contains('__NOT_CONFIGURED__')
          ? '还没配置 AI 服务，我暂时说不上话 🙂'
          : '我这边连接出错了：${result.split(':').skip(1).join(':')}';
    }
    setState(() {
      _messages[idx] = _Msg('assistant', reply);
      _busy = false;
      _mood = failed ? SpriteMood.idle : SpriteMood.happy;
    });
    await _saveSession();
    _resetMoodLater();
  }

  void _resetMoodLater() {
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted && !_busy) setState(() => _mood = SpriteMood.idle);
    });
  }

  Future<void> _confirmExpense() async {
    final p = _pending;
    if (p == null) return;
    final tripId = _pendingTripId;
    if (tripId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('还没有旅程，先建一段旅程再记账')),
      );
      return;
    }
    try {
      await createExpense(ref,
          tripId: tripId,
          category: p.category,
          amountCents: p.amountCents,
          date: DateTime.now(),
          note: p.note);
      // 标记"用精灵记过账"，供成就规则判定
      await ref.read(databaseProvider).markAchievementFlag('sprite_expense');
      if (!mounted) return;
      setState(() {
        _messages.add(_Msg('assistant',
            '记好啦 ✅ ${p.category.emoji} ${p.category.label} ${p.amountText}'));
        _pending = null;
        _mood = SpriteMood.happy;
      });
      await _saveSession();
      _resetMoodLater();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('记账失败：$e')));
    }
  }

  void _dismissPending() {
    setState(() {
      _pending = null;
      _mood = SpriteMood.idle;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final trips = ref.watch(tripListProvider).valueOrNull ?? const [];

    return Container(
      width: 306,
      constraints: const BoxConstraints(maxHeight: 430),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withAlpha(90)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withAlpha(60),
              blurRadius: 24,
              offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 头部（整条可拖拽移动小窗）
          GestureDetector(
            onPanStart: (d) => widget.onDragStart?.call(d.globalPosition),
            onPanUpdate: (d) => widget.onDragUpdate?.call(d.delta),
            child: Container(
              color: cs.surfaceContainerHighest.withAlpha(90),
              padding: const EdgeInsets.fromLTRB(10, 6, 4, 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 34,
                    height: 34,
                    child: TravelSprite(form: widget.form, mood: _mood, size: 34),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(widget.form.name,
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        Text(
                          _busy ? '正在想…' : '说点什么，或记一笔消费',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: cs.outline),
                        ),
                      ],
                    ),
                  ),
                  // 拖拽把手提示
                  Tooltip(
                    message: '按住这里可以拖动小窗',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(Icons.drag_indicator,
                          size: 18, color: cs.outlineVariant),
                    ),
                  ),
                  if (widget.onOpenFullChat != null)
                    IconButton(
                      icon: const Icon(Icons.open_in_full, size: 18),
                      tooltip: '全屏对话',
                      onPressed: widget.onOpenFullChat,
                    ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 19),
                    onPressed: () =>
                        ref.read(spriteChatOpenProvider.notifier).state = false,
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant.withAlpha(70)),

          // 消息
          Flexible(
            child: ListView(
              controller: _scroll,
              reverse: false,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              children: [
                if (_messages.isEmpty) _hint(theme, cs),
                for (final m in _messages) _bubble(theme, cs, m),
                if (_pending != null)
                  _pendingCard(theme, cs, trips),
              ],
            ),
          ),

          // 快捷指令
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Row(
              children: [
                for (final q in const [
                  '帮我写今天日志',
                  '这趟花了多少',
                  '推荐附近好吃的',
                  '总结这趟旅行',
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ActionChip(
                      label: Text(q, style: const TextStyle(fontSize: 11.5)),
                      onPressed: _busy ? null : () => _sendPreset(q),
                    ),
                  ),
              ],
            ),
          ),

          // 输入行
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    // 【临时诊断】把每次文本变化打到 logcat，用于定位"删除后回弹"。
                    // 抓完问题后应连同 _dbg() 一起删除。
                    onChanged: (v) => _dbg('onChanged', _input.value),
                    maxLines: 1,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      isDense: true,
                      // 不再给输入框加提示文案（原「比如：午餐 45」），留空即可。
                      filled: true,
                      fillColor: cs.surfaceContainerHighest,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                FilledButton(
                  onPressed: _busy ? null : () => _send(),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(44, 42), padding: EdgeInsets.zero),
                  child: const Icon(Icons.arrow_upward, size: 20),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _hint(ThemeData theme, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        children: [
          Text('${widget.form.name}在这里 👋',
              style: theme.textTheme.bodyMedium),
          const SizedBox(height: 6),
          Text('可以直接聊天，也可以说「午餐45」这种短句让我记账',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: cs.outline)),
        ],
      ),
    );
  }

  Widget _bubble(ThemeData theme, ColorScheme cs, _Msg m) {
    final me = m.role == 'user';
    return Align(
      alignment: me ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 230),
        decoration: BoxDecoration(
          color: me ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(13),
            topRight: const Radius.circular(13),
            bottomLeft: Radius.circular(me ? 13 : 4),
            bottomRight: Radius.circular(me ? 4 : 13),
          ),
        ),
        child: Text(
          m.text,
          style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: me ? cs.onPrimary : cs.onSurface),
        ),
      ),
    );
  }

  /// 记账确认卡：入账前一定让用户核对分类/金额/归属旅程。
  Widget _pendingCard(ThemeData theme, ColorScheme cs, List<Trip> trips) {
    final p = _pending!;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: p.category.color.withAlpha(24),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: p.category.color.withAlpha(90)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(p.category.emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${p.category.label} · ${p.amountText}',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('备注：${p.note}',
              style: theme.textTheme.bodySmall?.copyWith(color: cs.outline)),
          const SizedBox(height: 8),
          Text('计入旅程',
              style: theme.textTheme.labelSmall?.copyWith(color: cs.outline)),
          const SizedBox(height: 6),
          if (trips.isEmpty)
            Text('还没有旅程，先建一段才能记账',
                style: theme.textTheme.bodySmall?.copyWith(color: cs.error))
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final t in trips.reversed)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        // 用 ChoiceChip 而不是 Dropdown：
                        // 下拉弹层在小窗里容易被裁切且难以点选，胶囊一眼可见、一点即中。
                        selected: _pendingTripId == t.id,
                        showCheckmark: _pendingTripId == t.id,
                        label: Text(t.destination,
                            style: const TextStyle(fontSize: 12)),
                        labelStyle: TextStyle(
                          fontSize: 12,
                          fontWeight: _pendingTripId == t.id
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                        selectedColor: p.category.color.withAlpha(45),
                        side: BorderSide(
                          color: _pendingTripId == t.id
                              ? p.category.color
                              : cs.outlineVariant,
                          width: _pendingTripId == t.id ? 1.6 : 1,
                        ),
                        onSelected: (_) => setState(() => _pendingTripId = t.id),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: _dismissPending, child: const Text('不是记账')),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: _confirmExpense,
                style: FilledButton.styleFrom(
                    backgroundColor: p.category.color,
                    foregroundColor: Colors.white),
                child: const Text('确认入账'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
