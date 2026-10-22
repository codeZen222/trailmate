import 'dart:io';

import 'package:flutter/material.dart';
import '../../../models/profile_model.dart';
import '../../../widgets/mood/mood_effect_layer.dart';

/// 个人旅行档案卡——仿旅行证件版式：
/// 顶部标题带 + 左侧竖版证件照 + 右侧登记字段 + 统计条 + 底部机读码（MRZ）+ 徽标。
/// 配色由 [Profile.cardStyle] 决定，用户可在编辑页自选。
/// 外层套 RepaintBoundary 即可直接截成分享图。
class ProfileCard extends StatelessWidget {
  const ProfileCard({
    super.key,
    required this.profile,
    required this.stats,
  });

  final Profile profile;
  final ProfileStats stats;

  // 当前配色（来自用户选择）
  Color get _bandTop => profile.style.bandTop;
  Color get _bandBottom => profile.style.bandBottom;
  Color get _bodyTop => profile.style.bodyTop;
  Color get _bodyBottom => profile.style.bodyBottom;
  Color get _ink => profile.style.ink;
  Color get _inkSoft => profile.style.inkSoft;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 340,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(45), blurRadius: 18, offset: const Offset(0, 6)),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [_bodyTop, _bodyBottom],
                ),
              ),
            ),
          ),
          // 心情特效压在文字下层，会被截进分享图
          if (profile.mood != null)
            MoodEffectLayer(mood: profile.mood, seed: profile.nickname.hashCode & 0x3fff),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _titleBand(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _portrait(),
                    const SizedBox(width: 14),
                    Expanded(child: _fields()),
                  ],
                ),
              ),
              _statsRow(),
              _issueRow(),
              _mrz(),
            ],
          ),
        ],
      ),
    );
  }

  // ---------- 顶部标题带 ----------
  Widget _titleBand() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_bandTop, _bandBottom],
        ),
      ),
      child: Column(
        children: [
          Text(
            'TRAVEL  RESIDENT  CARD',
            style: TextStyle(
              color: profile.style.onBand.withAlpha(238),
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 3.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '旅行永久居留证',
            style: TextStyle(
              color: profile.style.onBand.withAlpha(180),
              fontSize: 10,
              letterSpacing: 4,
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 左侧证件照 ----------
  Widget _portrait() {
    return Container(
      width: 82,
      height: 106,
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(120),
        border: Border.all(color: _inkSoft.withAlpha(90)),
        borderRadius: BorderRadius.circular(4),
      ),
      clipBehavior: Clip.antiAlias,
      child: (profile.photoPath ?? '').isEmpty
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.person_outline, size: 30, color: _inkSoft.withAlpha(140)),
                const SizedBox(height: 6),
                Text('未上传\n证件照',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 9, color: _inkSoft.withAlpha(150), height: 1.3)),
              ],
            )
          : Image.file(
              File(profile.photoPath!),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  Icon(Icons.broken_image_outlined, size: 28, color: _inkSoft),
            ),
    );
  }

  // ---------- 右侧登记字段 ----------
  Widget _fields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _line('姓名 NAME', profile.nickname, strong: true),
        const SizedBox(height: 7),
        if ((profile.homeCity ?? '').isNotEmpty) ...[
          _line('常驻 RESIDENCE', profile.homeCity!),
          const SizedBox(height: 7),
        ],
        if (profile.travelDays != null) ...[
          _line('旅行 SINCE', '第 ${profile.travelDays} 天'),
          const SizedBox(height: 7),
        ],
        if (profile.travelStyles.isNotEmpty)
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: profile.travelStyles
                .take(4)
                .map((s) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _bandTop.withAlpha(28),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('#$s',
                          style: TextStyle(
                              fontSize: 9, color: _ink, fontWeight: FontWeight.w600)),
                    ))
                .toList(),
          ),
        if ((profile.bio ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '「${profile.bio}」',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontStyle: FontStyle.italic,
              color: _inkSoft,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }

  Widget _line(String label, String value, {bool strong = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: TextStyle(fontSize: 8, letterSpacing: 1, color: _inkSoft.withAlpha(200))),
        const SizedBox(height: 1),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: strong ? 15 : 11.5,
            fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
            color: _ink,
          ),
        ),
      ],
    );
  }

  // ---------- 统计条 ----------
  Widget _statsRow() {
    Widget cell(String v, String l) => Expanded(
          child: Column(
            children: [
              Text(v,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _ink)),
              const SizedBox(height: 1),
              Text(l, style: TextStyle(fontSize: 9, color: _inkSoft.withAlpha(210))),
            ],
          ),
        );
    Widget sep() => Container(width: 1, height: 22, color: _inkSoft.withAlpha(50));

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(70),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _inkSoft.withAlpha(50)),
      ),
      child: Row(
        children: [
          cell('${stats.cities}', '城市'),
          sep(),
          cell('${stats.trips}', '旅程'),
          sep(),
          cell('${stats.totalDays}', '天数'),
          sep(),
          cell('${stats.photos}', '照片'),
          sep(),
          cell('${stats.achievementsUnlocked}', '成就'),
        ],
      ),
    );
  }

  // ---------- 签发信息（仿身份证底部一对字段） ----------
  Widget _issueRow() {
    Widget item(String label, String value) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 8.5, letterSpacing: 0.8, color: _inkSoft.withAlpha(200))),
            const SizedBox(width: 5),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 10.5, fontWeight: FontWeight.w600, color: _ink)),
          ],
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: item('签发机关', profile.displayAuthority),
          ),
          item('有效期限', profile.displayValidity),
        ],
      ),
    );
  }

  // ---------- 底部机读码 ----------
  Widget _mrz() {
    const width = 34;
    String pad(String s) =>
        s.length >= width ? s.substring(0, width) : s.padRight(width, '<');

    final name = _asciiFold(profile.nickname);
    final l1 = pad('I<CN<<TRAVEL<<$name');
    final days = (profile.travelDays ?? stats.totalDays).toString().padLeft(6, '0');
    final l2 = pad('${stats.cities.toString().padLeft(3, '0')}<CN'
        '<$days<${stats.photos.toString().padLeft(4, '0')}'
        '<${stats.trips.toString().padLeft(2, '0')}');

    final mrzStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 9.5,
      letterSpacing: 0.6,
      height: 1.25,
      color: _ink,
    );

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(16, 9, 16, 10),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(95),
        border: Border(top: BorderSide(color: _inkSoft.withAlpha(60))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l1, style: mrzStyle),
                const SizedBox(height: 3),
                Text(l2, style: mrzStyle),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _badge(),
        ],
      ),
    );
  }

  /// 徽标：用 App 自有标识，不模仿真实证件的国徽/国旗。
  Widget _badge() {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [_bandTop, _bandBottom]),
      ),
      child: const Icon(Icons.explore, size: 15, color: Colors.white),
    );
  }

  /// 只保留 MRZ 允许的大写字母数字。
  static String _asciiFold(String s) {
    final out = s
        .toUpperCase()
        .split('')
        .where((c) => RegExp('[A-Z0-9]').hasMatch(c))
        .join();
    return out.length > 14 ? out.substring(0, 14) : out;
  }
}
