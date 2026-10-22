import 'dart:io';

import 'package:flutter/material.dart';
import '../../../database/app_database.dart' as db;
import '../../../widgets/footprint/stacked_photo_viewer.dart';

/// 日志正文下方的九宫格缩略图。
class ImageGrid extends StatelessWidget {
  final List<db.Image> images;

  const ImageGrid({super.key, required this.images});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    // 一次算好整份列表，避免每张缩略图各自重复构造
    final paths = images.map((i) => i.filePath).toList(growable: false);
    final captions = images.map((i) => i.aiDescription).toList(growable: false);
    final cell = (mq.size.width - 48) / 3;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < images.length; i++)
              GestureDetector(
                // 打开后左右滑动即可连续浏览，不必每看一张都退出重进
                onTap: () => StackedPhotoViewer.open(context,
                    paths: paths, initialIndex: i, captions: captions),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(
                        File(images[i].filePath),
                        width: cell,
                        height: cell,
                        fit: BoxFit.cover,
                        // 缩略图按显示尺寸解码，九张原图一起解会明显拖慢页面
                        cacheWidth: (cell * 2 * mq.devicePixelRatio).round(),
                        errorBuilder: (_, __, ___) => Container(
                          width: cell,
                          height: cell,
                          color: Colors.grey[200],
                          child: const Icon(Icons.broken_image,
                              color: Colors.grey),
                        ),
                      ),
                    ),
                    // 带 AI 描述的照片给个小标记，一眼看出哪张有说明
                    if ((images[i].aiDescription ?? '').trim().isNotEmpty)
                      const Positioned(
                        right: 5,
                        bottom: 5,
                        child: Icon(Icons.auto_awesome,
                            size: 13, color: Colors.white),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}
