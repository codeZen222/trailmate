import 'package:flutter/material.dart';
import '../../models/sprite_form.dart';

/// 一套皮肤 = 颜色 + 配件开关。绘制器只认 Skin，不认具体形象，
/// 因此加第 5 款只需再加一个预设。
class SpriteSkin {
  const SpriteSkin({
    required this.shellLight,
    required this.shellMid,
    required this.shellShadow,
    required this.rim,
    required this.visorTop,
    required this.visorBottom,
    required this.eye,
    required this.mouth,
    required this.core,
    required this.wingA,
    required this.wingB,
    required this.wingC,
    this.wings = true,
    this.wingCount = 4,
    this.halo = false,
    this.antenna = false,
    this.camera = false,
    this.backpack = false,
    this.starfield = false,
    this.circuits = false,
    this.chip = false,
    this.blush = true,
    this.glassHead = false,
    this.earDisc = true,
  });

  /// 外壳三段色：构成径向渐变的体积感（受光面 → 中间 → 阴影面）。
  final Color shellLight;
  final Color shellMid;
  final Color shellShadow;

  /// 边缘轮廓光（逆光感）。
  final Color rim;

  /// 镜面屏脸的上下色。
  final Color visorTop;
  final Color visorBottom;

  final Color eye;
  final Color mouth;

  /// 胸口发光核心。
  final Color core;

  /// 翅膀虹彩三段色。
  final Color wingA;
  final Color wingB;
  final Color wingC;

  final bool wings;
  final int wingCount;
  final bool halo;
  final bool antenna;
  final bool camera;
  final bool backpack;

  /// 头内星尘（玻璃穹顶款）。
  final bool starfield;

  /// 表面金色电路纹。
  final bool circuits;

  /// 手捧发光芯片。
  final bool chip;

  final bool blush;

  /// 头部画成透明玻璃穹顶而非实心壳。
  final bool glassHead;

  /// 两侧圆形耳盘。
  final bool earDisc;
}

class SpriteSkins {
  SpriteSkins._();

  static SpriteSkin of(SpriteForm form, {required bool dark}) {
    switch (form) {
      case SpriteForm.angel:
        return dark ? _angelDark : _angelLight;
      case SpriteForm.bubble:
        return dark ? _bubbleDark : _bubbleLight;
      case SpriteForm.cosmic:
        return dark ? _cosmicDark : _cosmicLight;
      case SpriteForm.travel:
        return dark ? _travelDark : _travelLight;
    }
  }

  // ---------------- 小羽 · 白羽仙子 ----------------

  static const _angelLight = SpriteSkin(
    shellLight: Color(0xFFFFFFFF),
    shellMid: Color(0xFFEFF2F8),
    shellShadow: Color(0xFFBFC9DA),
    rim: Color(0xFF9FD8FF),
    visorTop: Color(0xFF2A2350),
    visorBottom: Color(0xFF6E4FA8),
    eye: Color(0xFF6FE3FF),
    mouth: Color(0xFFFF8FC4),
    core: Color(0xFF4FC3F7),
    wingA: Color(0xFF9FE8FF),
    wingB: Color(0xFFC3B4FF),
    wingC: Color(0xFFFFB6E0),
    wings: true,
    wingCount: 4,
    earDisc: true,
  );

  static const _angelDark = SpriteSkin(
    shellLight: Color(0xFFE8EDF6),
    shellMid: Color(0xFFB9C4D8),
    shellShadow: Color(0xFF5A6580),
    rim: Color(0xFF7FD4FF),
    visorTop: Color(0xFF1A1436),
    visorBottom: Color(0xFF5B3F92),
    eye: Color(0xFF7BE9FF),
    mouth: Color(0xFFFF9ACB),
    core: Color(0xFF59CBFF),
    wingA: Color(0xFF7FD8FF),
    wingB: Color(0xFFB0A0FF),
    wingC: Color(0xFFFFA6D8),
    wings: true,
    wingCount: 4,
    earDisc: true,
  );

  // ---------------- 小泡 · 玻璃泡泡 ----------------

  static const _bubbleLight = SpriteSkin(
    shellLight: Color(0xFFFFFFFF),
    shellMid: Color(0xFFE6F4FF),
    shellShadow: Color(0xFFA9CBE8),
    rim: Color(0xFF8FE6FF),
    visorTop: Color(0xFFEAF6FF),
    visorBottom: Color(0xFFCDE9FF),
    eye: Color(0xFF2E7BD6),
    mouth: Color(0xFF7A5B48),
    core: Color(0xFF4FD0E8),
    wingA: Color(0xFFBFEFFF),
    wingB: Color(0xFFD8E4FF),
    wingC: Color(0xFFE9D6FF),
    wings: false,
    halo: true,
    glassHead: true,
    starfield: true,
    earDisc: false,
  );

  static const _bubbleDark = SpriteSkin(
    shellLight: Color(0xFFDCEAF8),
    shellMid: Color(0xFF9FC3E2),
    shellShadow: Color(0xFF44607F),
    rim: Color(0xFF7FE0FF),
    visorTop: Color(0xFF16324A),
    visorBottom: Color(0xFF2A5A82),
    eye: Color(0xFF7FD4FF),
    mouth: Color(0xFFBFA08C),
    core: Color(0xFF55DCF2),
    wingA: Color(0xFF8FDFFF),
    wingB: Color(0xFFA9C4FF),
    wingC: Color(0xFFCBAFFF),
    wings: false,
    halo: true,
    glassHead: true,
    starfield: true,
    earDisc: false,
  );

  // ---------------- 小星 · 星空金属 ----------------

  static const _cosmicLight = SpriteSkin(
    shellLight: Color(0xFFF2F1F8),
    shellMid: Color(0xFFC9C6D8),
    shellShadow: Color(0xFF77728C),
    rim: Color(0xFFFFD98A),
    visorTop: Color(0xFF241F36),
    visorBottom: Color(0xFF4A3F6B),
    eye: Color(0xFFFFE3A6),
    mouth: Color(0xFFE8CFA0),
    core: Color(0xFFFFC85C),
    wingA: Color(0xFFB7E8FF),
    wingB: Color(0xFFD6C4FF),
    wingC: Color(0xFFFFD9A8),
    wings: true,
    wingCount: 2,
    antenna: true,
    circuits: true,
    chip: true,
    earDisc: true,
  );

  static const _cosmicDark = SpriteSkin(
    shellLight: Color(0xFFD8D5E8),
    shellMid: Color(0xFF8E88A8),
    shellShadow: Color(0xFF3E3A52),
    rim: Color(0xFFFFD068),
    visorTop: Color(0xFF151022),
    visorBottom: Color(0xFF3A2F55),
    eye: Color(0xFFFFE0A0),
    mouth: Color(0xFFD9BC8C),
    core: Color(0xFFFFC24D),
    wingA: Color(0xFF8FD8FF),
    wingB: Color(0xFFBFA6FF),
    wingC: Color(0xFFFFCE8A),
    wings: true,
    wingCount: 2,
    antenna: true,
    circuits: true,
    chip: true,
    earDisc: true,
  );

  // ---------------- 小旅 · 旅行相机 ----------------

  static const _travelLight = SpriteSkin(
    shellLight: Color(0xFFFFFFFF),
    shellMid: Color(0xFFF0F4F3),
    shellShadow: Color(0xFFC2CFCB),
    rim: Color(0xFF8FE0C8),
    visorTop: Color(0xFFD6F7EE),
    visorBottom: Color(0xFF9FE6D4),
    eye: Color(0xFF2E8B73),
    mouth: Color(0xFF2E8B73),
    core: Color(0xFF4EC9AC),
    wingA: Color(0xFFCFF3E8),
    wingB: Color(0xFFDCE9FF),
    wingC: Color(0xFFFFE7C2),
    wings: false,
    backpack: true,
    camera: true,
    earDisc: true,
  );

  static const _travelDark = SpriteSkin(
    shellLight: Color(0xFFE9F2EF),
    shellMid: Color(0xFFAFC4BE),
    shellShadow: Color(0xFF4C5F5A),
    rim: Color(0xFF7FE3C6),
    visorTop: Color(0xFF17453B),
    visorBottom: Color(0xFF2C7A66),
    eye: Color(0xFF8FF0D2),
    mouth: Color(0xFF8FF0D2),
    core: Color(0xFF57D9B6),
    wingA: Color(0xFFA9E8D6),
    wingB: Color(0xFFBBD4FF),
    wingC: Color(0xFFFFDCA6),
    wings: false,
    backpack: true,
    camera: true,
    earDisc: true,
  );
}
