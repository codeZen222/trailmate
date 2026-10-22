import 'package:flutter/material.dart';

/// 精灵形象。参考用户给的四张 3D 渲染图，提炼出共同的造型语言：
/// 大头小身、镜面屏脸、径向渐变体积感、边缘轮廓光、虹彩翅膀、胸口发光核心。
///
/// 全部由 CustomPaint 以多层渐变绘制，**不是真 3D**（无透视与真实光照），
/// 但在 76px 悬浮尺寸下足以呈现柔和的立体渲染观感；
/// 好处是零图片资源、跟随主题色、深色模式自适应、表情可逐帧变化。
enum SpriteForm {
  /// 白羽仙子：白色头盔 + 深色镜面 + 四片虹彩翅膀 + 蓝色耳盘
  angel('angel', '小羽', '白羽仙子', Icons.smart_toy),

  /// 玻璃泡泡：透明穹顶头 + 内部星尘 + 头顶光环 + 腮红
  bubble('bubble', '小泡', '玻璃泡泡', Icons.bubble_chart),

  /// 星空金属：金属壳 + 天线星光 + 金色电路纹 + 手捧 AI 芯片
  cosmic('cosmic', '小星', '星空金属', Icons.auto_awesome),

  /// 旅行相机：薄荷绿屏脸 + 背包肩带 + 胸前 AI 徽章 + 手持相机
  travel('travel', '小旅', '旅行相机', Icons.camera_enhance);

  const SpriteForm(this.key, this.name, this.label, this.icon);

  /// 持久化标识。
  final String key;
  /// 名字（对话窗标题、打招呼用）。
  final String name;
  /// 设置页显示名。
  final String label;
  final IconData icon;

  static const SpriteForm fallback = SpriteForm.travel;

  static SpriteForm fromKey(String? k) {
    if (k == null || k.isEmpty) return fallback;
    for (final f in values) {
      if (f.key == k) return f;
    }
    return fallback;
  }
}

/// 精灵表情/动作状态。
enum SpriteMood {
  idle,
  happy,
  thinking,
  dragging,
  sleepy,
  speaking,
}
