import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/ai_service.dart';
import '../../providers/database_provider.dart';

const String _sessionsKey = 'ai_chat_sessions';

class _Msg {
  final String role; // user / assistant
  final String text;
  _Msg(this.role, this.text);

  Map<String, dynamic> toJson() => {'role': role, 'text': text};
  factory _Msg.fromJson(Map<String, dynamic> j) =>
      _Msg(j['role'] as String? ?? 'user', j['text'] as String? ?? '');
}

class _Session {
  final String id;
  List<_Msg> messages;
  DateTime updated;
  _Session({required this.id, required this.messages, required this.updated});

  String get title {
    final firstUser = messages.where((m) => m.role == 'user').firstOrNull;
    if (firstUser != null && firstUser.text.isNotEmpty) {
      return firstUser.text.length > 16 ? '${firstUser.text.substring(0, 16)}…' : firstUser.text;
    }
    return '新对话';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'updated': updated.toIso8601String(),
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  factory _Session.fromJson(Map<String, dynamic> j) => _Session(
        id: j['id'] as String,
        updated: DateTime.tryParse(j['updated'] as String? ?? '') ?? DateTime.now(),
        messages: ((j['messages'] as List?) ?? [])
            .map((e) => _Msg.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

/// 2.8：AI 旅行助手——多会话 + 流式输出。
class AiChatPage extends ConsumerStatefulWidget {
  const AiChatPage({super.key});

  @override
  ConsumerState<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends ConsumerState<AiChatPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  List<_Session> _sessions = [];
  int _current = 0;
  bool _sending = false;
  CancelToken? _cancel;

  static const _notConfigured = '__NOT_CONFIGURED__';
  static const _callFailedPrefix = '__CALL_FAILED__:';

  _Session get _cur => _sessions[_current];

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    final raw = await ref.read(databaseProvider).getSetting(_sessionsKey);
    List<_Session> loaded = [];
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        loaded = list
            .map((e) => _Session.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      } catch (_) {}
    }
    if (loaded.isEmpty) {
      loaded = [_Session(id: _newId(), messages: [], updated: DateTime.now())];
    }
    setState(() {
      _sessions = loaded;
      _current = 0;
    });
    _scrollToEnd();
  }

  Future<void> _persistSessions() async {
    // 每个会话最多留 40 条，最多留 20 个会话。
    final trimmed = _sessions.take(20).map((s) {
      if (s.messages.length > 40) s.messages = s.messages.sublist(s.messages.length - 40);
      return s;
    }).toList();
    await ref.read(databaseProvider)
        .setSetting(_sessionsKey, jsonEncode(trimmed.map((s) => s.toJson()).toList()));
  }

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  @override
  void dispose() {
    _cancel?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _newSession() {
    setState(() {
      _sessions.insert(0, _Session(id: _newId(), messages: [], updated: DateTime.now()));
      _current = 0;
    });
    _persistSessions();
    // 仅当抽屉打开时才关闭它；从 AppBar 按钮调用时不 pop（避免退出页面）
    if (Scaffold.of(context).isDrawerOpen) {
      Navigator.pop(context);
    }
  }

  void _openSession(int i) {
    setState(() => _current = i);
    Navigator.pop(context);
    _scrollToEnd();
  }

  Future<void> _deleteSession(int i) async {
    setState(() {
      _sessions.removeAt(i);
      if (_sessions.isEmpty) {
        _sessions.add(_Session(id: _newId(), messages: [], updated: DateTime.now()));
      }
      _current = _current.clamp(0, _sessions.length - 1);
    });
    await _persistSessions();
    if (mounted) Navigator.pop(context);
  }

  void _useSuggestion(String text) {
    _input.text = text;
    _input.selection = TextSelection.collapsed(offset: text.length);
    _send();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _cur.messages.add(_Msg('user', text));
      _cur.updated = DateTime.now();
      _input.clear();
      _sending = true;
    });
    _persistSessions();
    _scrollToEnd();

    final history = _cur.messages.map((m) => {'role': m.role, 'content': m.text}).toList();
    final svc = ref.read(aiServiceProvider);
    _cancel = CancelToken();

    // 先放一个空的 assistant 气泡，边收边填。
    final placeholder = _Msg('assistant', '');
    setState(() => _cur.messages.add(placeholder));
    var gotDelta = false;

    final reply = await svc.chatStream(history, cancelToken: _cancel, onChunk: (delta) {
      if (!mounted) return;
      gotDelta = true;
      setState(() {
        final last = _cur.messages.last;
        _cur.messages[_cur.messages.length - 1] = _Msg('assistant', last.text + delta);
      });
      _scrollToEnd(immediate: true);
    });
    if (!mounted) return;

    setState(() {
      if (!gotDelta) {
        // 没收到任何流式内容：按结果处理（未配置/失败/兜底）
        _cur.messages.removeLast();
        String shown = reply;
        if (reply == _notConfigured) {
          shown = '还没有配置 AI 服务哦，请到「设置 → AI 设置」填写 API Key 后再来找我。';
        } else if (reply.startsWith(_callFailedPrefix)) {
          shown = '调用失败：${reply.substring(_callFailedPrefix.length)}';
        } else if (reply != '__CANCELLED__') {
          shown = reply;
        }
        if (reply != '__CANCELLED__') _cur.messages.add(_Msg('assistant', shown));
      }
      _cur.updated = DateTime.now();
      _sending = false;
    });
    _persistSessions();
    _scrollToEnd();
  }

  void _stop() {
    _cancel?.cancel();
    setState(() => _sending = false);
  }

  void _scrollToEnd({bool immediate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildDrawer(theme),
      appBar: AppBar(
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: Text(_cur.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: '新建对话',
            onPressed: _newSession,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _cur.messages.isEmpty
                ? _buildEmpty(theme)
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(16),
                    itemCount: _cur.messages.length,
                    itemBuilder: (context, i) {
                      final m = _cur.messages[i];
                      final isStreamingPlaceholder =
                          _sending && i == _cur.messages.length - 1 && m.role == 'assistant' && m.text.isEmpty;
                      if (isStreamingPlaceholder) return _TypingBubble(theme: theme);
                      return _Bubble(msg: m, theme: theme);
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: '想去哪玩？问我吧…',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_sending)
                    FilledButton(
                      onPressed: _stop,
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(56, 48), padding: EdgeInsets.zero),
                      child: const Icon(Icons.stop),
                    )
                  else
                    FilledButton(
                      onPressed: _send,
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(56, 48), padding: EdgeInsets.zero),
                      child: const Icon(Icons.send),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer(ThemeData theme) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            ListTile(
              leading: Icon(Icons.smart_toy_outlined, color: theme.colorScheme.primary),
              title: Text('旅行助手', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              trailing: IconButton(icon: const Icon(Icons.edit_outlined), tooltip: '新建对话', onPressed: _newSession),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: _sessions.length,
                itemBuilder: (context, i) {
                  final s = _sessions[i];
                  return ListTile(
                    selected: i == _current,
                    selectedTileColor: theme.colorScheme.primaryContainer.withAlpha(60),
                    leading: const Icon(Icons.chat_bubble_outline, size: 20),
                    title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${s.messages.where((m) => m.role == 'user').length} 轮对话',
                        style: theme.textTheme.bodySmall),
                    onTap: () => _openSession(i),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'del') _deleteSession(i);
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'del', child: Text('删除')),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.smart_toy_outlined, size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text('嗨，我是你的旅行小助手', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('可以问我目的地推荐、行程规划、当地玩法。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
            const SizedBox(height: 20),
            Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: const [
              _Suggest('帮我推荐几个适合秋天的目的地'),
              _Suggest('三天两夜的成都行程怎么安排'),
              _Suggest('带娃去海边要注意什么'),
            ]),
          ],
        ),
      ),
    );
  }
}

class _Suggest extends StatelessWidget {
  final String text;
  const _Suggest(this.text);

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(text, style: const TextStyle(fontSize: 12)),
      onPressed: () {
        final state = context.findAncestorStateOfType<_AiChatPageState>();
        state?._useSuggestion(text);
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  final _Msg msg;
  final ThemeData theme;
  const _Bubble({required this.msg, required this.theme});

  @override
  Widget build(BuildContext context) {
    final isUser = msg.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: isUser ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(15),
            topRight: const Radius.circular(15),
            bottomLeft: Radius.circular(isUser ? 15 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 15),
          ),
        ),
        child: SelectableText(
          msg.text,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: isUser ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  final ThemeData theme;
  const _TypingBubble({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(15),
        ),
        child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.primary)),
      ),
    );
  }
}
