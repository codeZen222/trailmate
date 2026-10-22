import 'package:flutter/material.dart';
import '../poster_data.dart';
import 'poster_primitives.dart';

/// 模板二：极简杂志——大量留白、细分割线、超大细字地名、底部等宽数据。
class EditorialTemplate extends StatelessWidget {
  const EditorialTemplate({super.key, required this.data, this.width = 340});

  final TripPosterData data;
  final double width;

  static const _paper = Color(0xFFFFFFFF);
  static const _ink = Color(0xFF1A1A1A);
  static const _grey = Color(0xFF8C8C8C);
  static const _rule = Color(0xFFE2E2E2);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: _paper,
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withAlpha(40),
              blurRadius: 20,
              offset: const Offset(0, 7)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 刊头
            Row(
              children: [
                const Text('TRAVEL JOURNAL',
                    style: TextStyle(
                        fontSize: 9,
                        letterSpacing: 3,
                        color: _ink,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('NO.${data.days.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 9, letterSpacing: 1.5, color: _grey)),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(color: _rule, thickness: 1, height: 1),
            const SizedBox(height: 22),

            // 超大细字地名
            Text(
              data.destination,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.w300,
                height: 1.05,
                letterSpacing: 2,
                color: _ink,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              data.displayCaption,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 11, height: 1.6, color: _grey, letterSpacing: 1.2),
            ),
            const SizedBox(height: 20),

            // 三图条
            if (data.photoPaths.isNotEmpty) ...[
              SizedBox(
                height: 108,
                child: Row(
                  children: [
                    for (var i = 0; i < 3; i++) ...[
                      Expanded(
                        child: PhotoSlot(
                          path: _photoAt(i),
                          height: 108,
                          iconSize: 20,
                        ),
                      ),
                      if (i < 2) const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            Divider(color: _rule, thickness: 1, height: 1),
            const SizedBox(height: 14),

            if (data.notesExcerpt.isNotEmpty) ...[
              Text(
                data.notesExcerpt,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 11, height: 1.7, color: Color(0xFF4A4A4A)),
              ),
              const SizedBox(height: 14),
            ],

            // 等宽数据行
            Row(
              children: [
                _kv('天', '${data.days}'),
                _kv('城', '${data.cities.length}'),
                _kv('篇', '${data.logCount}'),
                _kv('张', '${data.photoCount}'),
              ],
            ),
            const SizedBox(height: 14),
            PosterCostLine(
                data: data, color: const Color(0xFF4A4A4A), alignEnd: true),
            Row(
              children: [
                const Text('DATE',
                    style: TextStyle(fontSize: 8, letterSpacing: 2, color: _grey)),
                const SizedBox(width: 8),
                Text(data.dateRange,
                    style: const TextStyle(
                        fontSize: 10, letterSpacing: 0.8, color: _ink)),
                const Spacer(),
                const Text('TrailMate',
                    style: TextStyle(
                        fontSize: 8.5, letterSpacing: 2.2, color: _grey)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String? _photoAt(int i) {
    // 第 0 张用主图，后两张从补充图里取，不足则循环回主图
    if (i == 0) return data.mainPhoto;
    final extras = data.extraPhotos(max: 8);
    if (extras.isEmpty) return data.mainPhoto;
    return extras[(i - 1) % extras.length];
  }

  Widget _kv(String k, String v) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(v,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w300, color: _ink)),
            const SizedBox(height: 2),
            Text(k, style: const TextStyle(fontSize: 9, color: _grey, letterSpacing: 1)),
          ],
        ),
      );
}
