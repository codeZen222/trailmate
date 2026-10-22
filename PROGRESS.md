# TrailMate 开发进度交接（自动保存）

> 最后更新：本次会话结束。明天从这里继续即可。

---

## ✅ APK 打包已跑通（本次会话）

## 🗺 第三十一轮：足迹只留省级点亮地图 + 锁定全境 + 城市看图（47.5MB，未安装）

用户要求：① 去掉缩放 ② 只保留中国地图 ③ 只留有省份点亮的那个足迹页
④ 点亮点城市按参考图展示照片 ⑤ 也能查看城市详情。

### 一、删除旧三视图足迹页（连带清理）
`footprint_map_page.dart` 已删。改指向 `ProvinceMapPage` 的两处引用：
- `home_page.dart` 底部 Tab 第 2 页
- `app_router.dart` 的 footprint 路由
**顺带清掉三个因此孤立的组件**（grep 确认零外部引用才删）：
`city_photo_float_card.dart`、`footprint_share_image.dart`、`world_map.dart`（本来就是死代码）
> 第一次用 PowerShell 管道查引用写法有误、结果不可信，改用 grep 工具重查后才动手删。

### 二、地图锁死为中国全境
```dart
zoomGesturesEnabled: false, scrollGesturesEnabled: false,
minMaxZoomPreference: const amap.MinMaxZoomPreference(_homeZoom, _homeZoom),
limitBounds: LatLngBounds(southwest: (3.0,73.0), northeast: (54.0,135.5)),
```
- **gmm 没有 `minZoom`/`maxZoom`/`zoomControlsEnabled` 参数**，缩放区间要用 `MinMaxZoomPreference`
- `MinMaxZoomPreference` 在 **map 包**不在 base 包；构造是 const
- **`LatLngBounds` 不是 const 构造**，只能给它的两个 LatLng 参数加 const
- 删掉 AppBar「全景」按钮（与锁定语义冲突）；`gestureRecognizers` 整块移除
- **回溯时不再移动相机**：跟随飞机会与"不可拖拽"设定冲突导致画面乱晃，故 `_fitBounds` 一并删除

### 三、点城市 → 堆叠看照片 + 可查详情
- `StackedPhotoViewer.open()` 新增 `subtitle` 与 `onDetails` 参数
- 副标题显示「省份 · 2024.07 首访 · 去过 N 次」，让照片页也有信息量
- 底部「查看城市详情」按钮 → `CityDetailSheet.show(context, f)`
  （**该类原先没有 show() 静态方法**，补了一个标准 showModalBottomSheet 入口）
- 无照片时不弹空查看器，直接开详情并提示

### 四、修掉一个我自己写出来的真 bug
`_planeAt()` 原先按**采样点索引**线性插值，而 `_sampleTrack` 给每一段都固定采 24 个点——
意味着"上海→杭州"和"上海→乌鲁木齐"点数相同，**飞机在长途段会飞得极快、短途段慢吞吞**。
改为按 `_cumLen` **累计弧长**换算进度，全程视觉速度一致。
（`_rebuildLengths`/`_planeDistance` 之前算了却没用上，属于我写的无用代码；现在真正接上了。）
`perSeg` 提为 `_samplePerSegment` 常量，避免两处硬编码不同步。

**状态**：analyze 零错误，APK 47.5MB 已构建。设备持续离线未安装。

---

## ✈️ 第三十轮：飞机朝向 + 自查补齐四个遗漏（47.7MB，未安装-设备离线）

### 一、飞机朝向跟随航向（用户要求）
- **弃用 ✈ 字形**：字体渲染差异大且无法可靠旋转 → 改**自绘机翼 Path**（机头朝 -Y 为 0°），
  `canvas.rotate(angle)` 后烘焙成位图
- `_bearing()` 用**大圆初始方位角公式**
  `atan2(sinΔλ·cosφ2, cosφ1·sinφ2 − sinφ1·cosφ2·cosΔλ)`，结果归一到 0..360
- `_bearingAt()` 取进度点**前方 3 个采样点**的切线方向，避免重采样抖动导致机身乱转；
  到终点时回看后方 3 点沿用最后一段方向
- **角度量化 16 档（每 22.5°）**缓存位图：全 360° 逐度生成太浪费内存，地图上肉眼分不出差别
- `_warmPlaneIcons()` 在回溯开始前一次性生成全部档位——否则飞行途中飞机会先消失再出现
- 取不到对应档位时**回退用任意已缓存档**，宁可角度略偏也不要飞机闪烁消失

### 二、自查发现的四个真实遗漏（不是凭记忆，逐项 grep 核对）
| 遗漏 | 后果 | 处理 |
|---|---|---|
| `provinceVisitCountsProvider` 定义了无人用 | 死代码（省级统计走 `provinceStatsProvider`） | **删除** |
| `unresolvedFootprintsProvider` 定义了 UI 没用 | 新地图上看不到"哪些城市缺坐标" | 加右上角「N 城无坐标」chip |
| `groupedByTrip()` 写了没调用 | 回溯只能按年，**更合理的按旅程分段没接上** | 接入回溯条 |
| 旧页补坐标入口在新地图缺失 | 发现缺位却**无处可修** | chip 点击直达 `FixCoordsSheet.show()`，回来后 invalidate 两个 provider |

### 三、回溯范围升级为三种
`全部历史 / 某一年 / 单条旅程`。
**为什么按旅程分段更对**：一次旅行不会被元旦拦腰截断——按年切会把"12月出发1月回来"
的同一趟行程拆成两段，甚至把不同年份的城市连成穿越全国的假线。
`_trackTrip` 与 `_trackYear` 互斥，选一个自动清另一个。

### 踩的坑
- `Marker` 图标一旦生成就不能改，所以朝向必须**预生成多档位图**而非运行时旋转
- Dart 标识符虽允许 Unicode，但 `φ1`/`Δλ` 这类希腊字母在部分工具链易出问题 → 换 ASCII 名
- `FixCoordsSheet` 自带 `static Future<void> show(context)`，我一开始误当普通 widget 用
  `Navigator.push` + `.then((changed))` —— 它返回 void，没有 changed 返回值
- `_startFly` 因需 `await _warmPlaneIcons()` 改为 async

**状态**：analyze 零错误，APK 47.7MB 已构建。设备持续离线未安装。

---

## 🗺 第二十九轮：足迹省级点亮地图（四阶段全部完成，未安装-设备离线）
最新 release：`build\app\outputs\flutter-apk\app-release.apk`（47.6MB）√ Built，analyze 零错误

用户要求：按省份点亮 + 四级亮度 + 市级亮点 + 时间连线 + 卡片堆叠看图 + 飞机回溯，
并明确「不再使用高德地图底图，但定位要准确」。

### 先验证的三个前提（都通过才动手）
1. **高德 Web 服务 Key 实测有效**：`cf50a8...2451`，济阳区能精确到区
   —— 但第 4 次请求即返回 `CUQPS_HAS_EXCEEDED_THE_LIMIT`，**免费档 QPS 极低**
2. **DataV.GeoAtlas 省界数据合规**：35 要素含 `710000 台湾省`/`810000 香港`/`820000 澳门`/海南，
   另有 `100000_JD` = **九段线 MultiPolygon 含 10 段** ✅
3. **体积**：原始 569KB → 坐标保留 3 位小数 415KB → gzip 约 118KB

### ⚠️ 与用户的方案协商结果（重要）
用户原话"不再使用高德地图"，但我指出**边界政治合规风险**（漏画台湾/南海是严重问题），
且自绘需自行核对领土完整性。**用户最终选择：高德底图 + 省级填色叠加**。
实现：`MapType.navi` + `labelsEnabled: false` → 只剩干净轮廓，其上叠 34 省 Polygon 发光填色。
定位则用**高德 Web 服务地理编码**兜底（只查坐标不参与渲染，与底图选择无关）。

### 关键插件限制（gmm_amap_flutter_map 3.1.4 实测）
- **`Polygon` 没有 `onTap`** → "点省份看详情"无法直接点省，改为**经城市亮点触发**
- `Marker.onTap` 是 `ArgumentCallback<String>`，签名必须写 `(String id)`
- `toByteData` 是**异步**的，写成同步会拿不到位图（第一版就踩了）
- 集合展开 `...` 不能出现在命名参数位置，markers 合并要用 `{...a, ...b}` 字面量
- `Factory` 来自 `foundation.dart`，`OneSequenceGestureRecognizer` 来自 `gestures.dart`，
  analyzer 的 unnecessary_import 提示在这处**不准**，删了会编译失败

### 交付内容
1. **地理编码服务** `services/amap_geocoding_service.dart`
   - 串行 + **420ms 强制节流**（应对低 QPS）、同地址并发请求合并、内存缓存
   - 结果写入 settings 表（键 `geo_<地名>`）持久化，避免重复请求
   - `backfillMissingFootprints()` 批量回填 (0,0) 记录
   - app.dart 启动流程：先离线词表回填 → 再高德兜底（`unawaited`，不拖慢启动）
2. **省界几何** `models/province_shape.dart` + `assets/geo/china_provinces.json`
   - GeoJSON MultiPolygon 是 `[多边形][环][点]` **三层嵌套**，少解析一层就会把经度当坐标对
   - `stripProvinceSuffix` 剥全称；`ChinaProvinces.load()` 失败返回空集合不崩
3. **省级统计** `providers/province_stats_provider.dart`
   - `VisitTier`：**0 / 1-3 / 4-6 / >6** 四级（按用户指定）
   - 城市→省归属：文本剥省名 → `kProvinceCities` 反查 → 归不进进 `unassignedCitiesProvider` **如实提示不硬塞**
   - 暗/亮双套 `fillFor(tier)` 配色
4. **轨迹模型** `providers/journey_provider.dart`
   - 按 `firstVisitedAt` 串联有坐标城市；(0,0) 排除（否则画到几内亚湾）
   - `forYear(y)` 支持按年切片；`provinceVisitCountsProvider`
   - drift 行对象需映射为模型 Footprint（类型不同源）
5. **省级地图页** `pages/footprint/province_map_page.dart`
   - 34 省发光填色 + 城市亮点 + 统计条 + 四级图例 + 省份详情面板 + 「N 城未归类」提示
   - **大圆插值(Slerp)** 重采样轨迹 → 视觉上呈自然弧线而非直线弦；
     距离用 **Haversine** 而非平面勾股（高纬度不失真）
   - 三层 Polyline（宽光晕+主线+细亮线）；回溯时只画已飞过部分形成拖尾
   - ✈️ 飞机 marker：全程约 9s / 40ms 一帧，相机跟随，年份范围可切「全部/某年」
   - 入口：足迹页 AppBar 🌐 图标
6. **卡片堆叠看图器** `widgets/footprint/stacked_photo_viewer.dart`
   - 当前图清晰、相邻卡缩放+旋转+压暗+横移，PageView 跟手拖拽切换
   - 顶部 `n / total`、底部缩略图条、左右箭头、点击空白关闭
   - `Image.file` **不支持 loadingBuilder**（那是网络图专用），用了会编译失败
   - `cacheWidth: 1400` 防大图 OOM

### 待办
- 装包验收（设备一直离线）
- 飞机朝向跟随航段角度（当前固定 ✈ 字形，未按 bearing 旋转）

---

## 🎨 第二十八轮：应用氛围背景（47.4MB，未安装-设备离线）

用户要求优化应用背景，可联网搜索或自行设计。

### 现状问题
`_refine()` 里 `scaffoldBackgroundColor: surfaceContainerLowest` —— **纯单色**，所以整体显得平。

### 设计依据
搜索确认当前主流做法是 "subtle gradient backgrounds for depth and warmth" 与 mesh gradient
（参考 [lowhung/wagwan 的同类 issue](https://github.com/lowhung/wagwan/issues/2)、
[Mesh Gradients 类 App](https://apps.apple.com/pt/app/gradientes-mesh-gradients/id6444388499)）。
据此自设计，**不引入任何图片或依赖**。

### 实现：底色渐变 + 三枚角落柔光
新增 `core/theme/app_background.dart`：
- `BackgroundPalette`：baseTop/baseBottom + 三个光斑色 + blobAlpha
- `AppBackgrounds`：**5 主题 × 明暗 = 10 套配方**，全部低饱和；
  浅色 blobAlpha 70-92，深色 58-72（暗背景上亮块会刺眼，故更克制）
- `AppBackground` widget：`Stack[背景, child]`，child 为空时只画背景
- **光斑用 RadialGradient 羽化，不用 MaskFilter.blur / BackdropFilter**
  —— 它整屏常驻，必须便宜；且无动画

### 接线
- `app_theme.dart`：`scaffoldBackgroundColor` 改为 **`Colors.transparent`**，由背景层供色
- `app.dart` builder 层次：**氛围背景 → SpriteOverlay(页面) → 精灵**；
  brightness 从 themeMode 解析（system 时取 `MediaQuery.platformBrightnessOf`）
- `settings_provider.dart`：新增 `backgroundProvider`（键 `ambient_background_enabled`，默认开）
- `settings_page.dart`：外观区加「氛围背景」开关，副标题随状态变化
- 关闭时 `DecoratedBox` 用 `color: baseBottom` 且 gradient 为 null —— **真纯色**，
  不是"只去掉光斑还留着渐变"（第一版就是这个语义错误，已改）

### 自查修正
1. `_blob` 里 `alignment: Alignment`（写成了类型名）→ 参数改名 `align`
2. 深色 sunset 预览发棕发浊 → base 去饱和到 #171514/#1A1817、blobAlpha 68→52
3. 预览脚本 `contact_sheet` 标题色与画布底色相同导致文字隐形 → 分开取色

### 用预览图代替实机验证
设备离线且我无法渲染 Flutter，故写 PIL 脚本按**同一套参数**出预览图
（`_bg_preview/light.png`、`dark.png`），并叠一层模拟 UI（标题/三张卡片/底部导航）
以判断背景是否干扰可读性。脚本用完已删除，预览图保留给用户审核。
中文在预览里显示为方框（arial 无 CJK 字形），不影响配色判断。

**状态**：analyze 零错误，APK 已构建（47.4MB）。设备离线未安装。

---

## 🐛 第二十七轮：城市统计偏低（两个独立根因，已用脚本实证）
最新 release：`build\app\outputs\flutter-apk\app-release.apk`（47.4MB）√ Built，analyze 零错误
**设备离线，未安装。**

用户报：成就的城市数与足迹城市数都比实际少。

### 排查方法：不猜，写脚本实证
临时建 `_geo_check.dart` 拿 37 个真实地名跑 `cityOf()`，结果触目：
- **8 个直辖市样本全部返回 NULL**（北京/上海/天津/重庆，带不带"市"都丢）
- "山东省济南市" → **"省济南"**、"西藏自治区拉萨" → **"自治区拉萨"**（省名后缀没剥）
- "北京市朝阳区" → **"市朝阳"**、"上海市浦东新区" → **"市浦东新"**
- "黔东南苗族侗族自治州" → "黔东"（惰性正则取了最短前缀）
- "成都-宽窄巷子" 完全没截断
跑完删除脚本。

### 根因一：`cityOf()` 的直辖市回填是死代码
`if (t.isEmpty) return null;` 写在直辖市回填循环**之前** —— 而恰恰是"北京市"剥成空
才需要回填，永远执行不到。**四个直辖市全部丢失**。

重写 `lib/utils/geo_naming.dart` 的 `cityOf()`：
1. 先按分隔符截断（含 `-` `—` `·` `/` 空格等）
2. **直辖市优先短路**：`t == m || t.startsWith('${m}市')` → 直接返回 m（后面的区不再剥）
3. 自治州：用 `_c2p.keys` 做**最长前缀匹配**（"黔东南苗族侗族自治州"→黔东南），
   正则 `^([\u4e00-\u9fa5]{2,6}?)(?:[\u4e00-\u9fa5]*族)+自治州$` 退为兜底
4. 省级前缀改为**带全称形式**匹配（`$p省`/`$p市`/`$p自治区`/`$p特别行政区` + 五个自治区
   完整民族称谓），且 `_provincesByLength` **按长度降序**，保证"内蒙古自治区"先于"内蒙古"
5. 只写了省名时回落到省会 `_capitalOf()`
6. 尾缀表加 `新区`，并补剥一次开头的 `市/县/区` 残留
复跑诊断：**丢失 0 / 37**，黔东南→黔东南(贵州)、湘西→湘西(湖南)、延边→延边(吉林) 全对。

### 根因二：坐标缺失的城市被静默过滤
`_visibleCities()` 过滤掉 `(0,0)`，而**济阳不在离线词表里** → 当初写成 (0,0) →
既上不了图、也不计入"点亮 N 城"。实测确认：泰安/济南/烟台/石家庄/洛阳 有坐标，**济阳 没有**。

三项修复：
1. **地图提示条改为如实报告**：`点亮 N 城 · M 省 · K 城待补坐标`，不再静默少算
2. **离线词表补 60+ 个常见县级目的地**（济阳/凤凰/镇远/荔波/建水/元阳/腾冲/黟县/曲阜/
   蓬莱/色达/丹巴/汶川/漠河/禾木/特克斯/平潭/开平/井冈山…）
   —— 首批有 5 个与原表重复触发 `equal_keys_in_const_map`，已去重
3. **启动自愈回填** `AppDatabase.backfillFootprintCoords()`：
   坐标是创建旅程那一刻写死的，词表扩充后老记录仍是 (0,0)。
   启动时扫一遍 (0,0) 记录用新词表重解析。**济阳这类会自己回来**。
   在 `app.dart` 用 `_bootstrapped` 标志做一次性 post-frame 调用，顺带跑一次 `checkAchievements`

### 其他
- `unnecessary_late`：顶层 final 本就惰性初始化，去掉 `late`

---

## 🏅 第二十六轮：年度回顾三处修复 + 成就系统扩展（37 个 / 规则引擎）
最新 release：`build\app\outputs\flutter-apk\app-release.apk`（47.3MB）√ Built，analyze 零错误
**设备未连接，本包含第二十四~二十六轮改动，尚未安装。**

### 用户报的三个问题（均已修）
1. **切年份不回到第一页**：`_selectYear` 只 setState 未重置 PageView
   → 加 `_page = 0; _pager.jumpToPage(0)`
2. **"走过 3 城却有 4 个首访"（不可能的结果）**：根因是**两套独立数据源**——
   `cities` 取自旅程目的地+日志 GPS 城市，`newCities` 却取自 footprints.firstVisitedAt 年份，
   且城市名未归一化（"泰安" vs "泰安市" 会算两座）。
   修复：**统一以"该年出发的旅程"为唯一次元**；所有城市名先过 `cityOf()` 归一化；
   **强制 `newCities = cities.where(isFirstVisit)`，保证 首访 ⊆ 走过**。
   顺带把 logCount/photoCount/月度/花费全部改为同一口径
   （之前 photoCount 累加全部、photos 列表却按年筛选；花费按日期年而日均按旅程天数 → 分子分母不同源）
3. **旅程下 5 颗空心星"是假的"**：星星**功能正常**（可点击），问题是 5 个空心星看起来像
   "评分为 0"的**展示**，没有"这是输入控件"的暗示 → 加文字提示
   「点击星星给这趟旅行评分」/「N 分 · 再点同一颗可清除」，未评分时星星降透明度。
   另修：`onRatingChanged` 原先 async 未 await 且无错误处理 → 改为 await + 失败弹提示 +
   `invalidate(tripByIdProvider)`；清除逻辑从"只有点第 1 颗才清零"改为"点当前分数的同一颗即清零"

### 成就系统扩展（用户确认：37 个全做 / 规则引擎 / 平滑合并）
- 新增 `services/achievement_rules.dart`：
  - `AchievementMetrics.compute()` 一次算出全部指标（城市/省份归一化去重、连续记录天数、
    活跃年份、深夜日志、跨年旅程、心情种类、晴雨反差、连续同心情、消费各维度、
    南北纬度跨度、单趟跨城、档案完整度、5 个行为标记）
  - `AchievementRule.parse()` 解析 `metric>=N` / `metric==N` / `flag` 三种规则串；
    `test()` 判定、`progress()` 出进度
  - `kMetricLabels` + `ruleToHint()` 把规则串翻译成「城市 7/10」
  - `Rarity` 四级（普通/稀有/史诗/传说）+ `kSeriesMembers` 六大系列映射
  - **37 个成就定义**（行者6/坚持7/情绪6/账本6/地图6/彩蛋7）
- DB：`achievements` 加 `rarity` 列（**用 `Constant` 不是 `Value`**），`schemaVersion 3→4`
- **播种改为按 name 幂等 upsert**：`name` 上没有唯一索引，原 `insertOnConflictUpdate`
  对自增 id 无效会重复插入；改为先查后写，且**更新时绝不触碰 unlockedAt**（用户进度不丢）
- `checkAchievements()` 从硬编码 if 串改为**规则引擎驱动**，返回本次新解锁项
- 新增 `achievementProgress()` 与 `achievementsWithProgressProvider`（带真实进度）
- 成就页重写：总进度头 + 六大系列分组 + 每行**进度条与「还差 N」**+ 稀有度配色与徽章
  + 解锁横幅（顶部滑入，逐条间隔 900ms）
- 新增 `services/achievement_flow.dart` 的 `runAchievementCheck()`：统计页与成就页共用，
  解锁时**精灵进入 happy 表情庆祝**（`spriteCelebrationProvider` 计数器信号，复用已有表情）
- 5 个行为标记已埋点：精灵记账 / 打开年报 / 分享成果(4 个出口) / 连线回看 / 补坐标

### 本轮踩的坑
1. `AchievementRule.parse` 里 `>=` 分支误传 `gte: false` → 全部 `>=` 规则退化成 `==`（严重，已修）
2. 规则正则 `[a-z_]+` 不匹配含数字的 `max_trip_spend` → 字符类加 `0-9`
3. 写了 `rated_trips==999999` 的临时把戏 → 改为真实指标 `all_rated`（≥3 趟且全评分）
4. 为逃避 `import 'dart:convert'` 写了一长串无意义间接跳转 → 直接 import 重写
5. drift `withDefault` 要 `Constant` 不是 `Value`；改完**必须重跑 build_runner** 否则 .g.dart 仍报错
6. `unlockAchievement` 被规则引擎取代后成为死代码且缺 rarity 参数 → 确认无调用者后删除
7. `a.copyWith(unlockedAt:)` 与生成签名不合 → 改返回轻量 record `({name, icon})`
8. `use_build_context_synchronously`：把 `ScaffoldMessenger`/`Overlay` 提到**所有 await 之前**捕获，
   并提供 `showWith(OverlayState)` 入口，而不是加 ignore 注释

---

## 🗺 第二十五轮：足迹页重构（三视图 + 时间筛选 + 补坐标 + 分享地图，22:13 包，已安装）
最新 release：`build\app\outputs\flutter-apk\app-release.apk`（47.3MB，10-11 22:13）√ Built，analyze 零错误
`adb install -r` → Success。

**用户反馈**：点击标记直接被放大、展开一堆线路太乱、体感差 → 要求优化并拓展。

### 诊断出的两个语义级错误（不是调参能解决的）
1. **连线常显且语义错**：`_routePts` 把**所有城市按 firstVisitedAt 串成一条线**并三层叠加常显。
   "首次到访时间顺序"根本不是行程——「洛阳→泰安→济阳」是三次独立出行，不是一条路线。
2. **点击 zoom 到 11**：`_selectCity` 里 `moveCamera(newLatLngZoom(..., 11))`，
   从 5.5 全国视角硬跳到城市级，丢失全局语境，看完还得手动缩回去。

### 交互修复
- **点击标记完全不动相机**（能点到说明已在屏上）；只高亮 + 弹浮卡
- 放大改为**用户主动触发**：浮卡新增「放大看看」按钮 → `newLatLngZoom(zoom 9.5)`
- **连线默认不显示**，进页面是干净点阵
- 浮卡底部按钮改为「放大看看 | 城市详情」两枚并列

### 三视图模式（左上角切换）
- **点亮**（默认）：城市标记**半径随到访次数**分 s/m/l 三档（18/21/24）
- **连线**：**按旅程分段**，每次旅行一条独立路径 + 8 色调色板循环着色，
  双层描边（12px 低透明光晕 + 5px 实线）；回放按钮只在此模式出现
- **热力**：径向渐变圆斑，半径与颜色随 visitCount 从绿渐变到红
  （插件**不支持 Circle 覆盖物**，故用 Canvas 画位图 BitmapDescriptor 实现）

### 拓展功能（6 项全做）
1. **时间轴筛选**：右上角年份 chips（全部/各年），口径为**"截至该年"累计**，
   切换后自动 `_fitAll()` 框回可见范围
2. **全景按钮**：`CameraUpdate.newLatLngBounds` 框回所有可见城市（单点时加 eps 防退化）
3. **视角记忆**：`onCameraMove` 记录 `_lastTarget/_lastZoom`，切 tab 回来不重置
4. **想去 vs 去过**：档案 `bucketList` 中能解析坐标的，以**空心紫环标记**画在地图上
   （已在 footprints 里的城市自动排除，不重复显示）
5. **城市花费**：详情弹窗加第三格「花费」，`getExpenseCentsByCity` 按目的地文本匹配旅程求和
6. **补坐标入口**：`FixCoordsSheet` 列出所有 (0,0) 足迹 → 在离线词表搜索选坐标 / 用当前定位。
   列表页里坐标缺失的城市也显式标"坐标缺失·地图上看不到"并给修复入口
7. **分享足迹地图**：`controller.takeSnapshot()` → `FootprintShareImage.compose`
   **自己重绘统计底栏**（原生地图截图不含 Flutter 覆盖层），合成城市/省份/旅程/照片四格数据卡；
   合成失败降级为分享纯地图截图

### 新增文件
- `utils/geo_naming.dart` — `provinceOf()`/`cityOf()` + 34 省 × 主要城市映射表（约 300 城）。
  **数据边界已注明**：文本省名前缀 → 城市反查表 → 都没命中返回 null 计入"未归类"，
  不猜。因此省份数是**下限**。hint 条显示「点亮 N 城 · M 省」
- `models/footprint_route.dart` — TripRoute / RoutePoint（按日志日期顺序取 GPS 点，相邻同坐标去重）
- `pages/footprint/widgets/fix_coords_sheet.dart`
- `pages/footprint/widgets/footprint_share_image.dart`

### 顺带修的既有问题
- `GeoCoder` 只暴露 lookup，无法搜索 → 加 `knownCities` 与 `search(query)`
- `LocationService` 的 provider 是日志编辑器里的**私有** `_locationServiceProvider`
  → 提到 `location_service.dart` 里公开为 `locationServiceProvider` 供复用
- 列表页 `RefreshIndicator(onRefresh: () async {})` **又是空实现** → 改为真正 refresh
- 位图缓存键从 `city|sel` 升级为 `kind|city|variant+bucket`，
  切模式/切选中**不清缓存**，避免标记闪烁

### 本轮踩的坑（analyze 首轮报 11 项）
1. drift 级联里 `..where(e => ...)` **不带括号会被解析器吃掉** → 必须写 `..where((x) => ...)`
2. `ui.Image` **没有 `toPicture()`** → 改用 `canvas.drawImageRect`
3. `(String,String)` record **不支持 `[]` 索引** → 用 `.$1`/`.$2`
4. `Uint8List` 在 `dart:ui` 文件里未定义 → 需 `import 'dart:typed_data'`
5. **字段无法类型提升**：`if (_year == null) return; ... <= _year` 仍报 int? → 拷成局部变量 `final y = _year`
6. `final c = const Offset(...)` → 应为 `const c = Offset(...)`
7. 误引用不存在的 `getTemporaryDirectoryLazy` / `footprintListProviderSelf` / `footprint.province`

---

## 📖 第二十四轮：年度回顾扩展为滑动卡片式年报（21:21 包，已安装）
最新 release：`build\app\outputs\flutter-apk\app-release.apk`（47.2MB，10-11 21:21）√ Built，analyze 零错误
`adb install -r` → Success。

**原状**：只有 3 个数字 + 一个"最佳旅程"（实为最长旅程，标签起错）+ 纯列表；
且 `RefreshIndicator(onRefresh: () async {})` 是**空实现**，下拉刷新点了没反应。

**改为**：9 张可左右滑动的卡片（Wrapped 式体验），每页可单独分享。

### 新增 `services/year_review_data.dart`（244 行）
`YearReviewData.build(db, year)` 一次聚合完毕，页面卡片只读不算：
trips/totalDays/logCount/photoCount/cities/newCities/months(12)/highlights/
longest/shortest/expenseCents/expenseByCategory/moodCounts/photoWall(≤12)/
tagCounts/unlockedAchievements/coverPhoto/totalPhotosEver
派生：`busiestMonth`、`dailySpendCents`、`topMood`、`topCategory`、`isEmpty`。
`_cityOf()` 从"河南洛阳"剥省级前缀取"洛阳"（覆盖 34 省级行政区正则）。

### 9 张卡片
1. **封面** 大图 + 68px 年份 + 总览语 + 3 张小图（无图退主题渐变）
2. **数字** 3×2 六格（出发/天数/城市/日志/照片/花费）+ 三条洞察文案
3. **月份** 12 月柱状（复用 BarChart）+ 有出行月份列表
4. **城市** 编号清单，**首访城市打「首访」标**（来自 footprints.firstVisitedAt 年份）
5. **高光旅程** 按评分排序 Top3 带封面缩略图与星级 + 最长/最短对比条
6. **心情天气** 各心情占比条形（用 MoodType.accent 着色）+ 空态引导
7. **钱去哪儿了** DonutChart 环形 + RankBars 排行 + 日均花费；空态提示可用精灵记账
8. **照片墙** 最多 12 张九宫格
9. **结尾** 年度标签 Top6 + 新解锁成就 + 结语卡

### 分享
`PageView` 每张卡外套 `RepaintBoundary(key: _cardKeys[i])`，
AppBar 分享按钮截**当前页**（pixelRatio 3.0）→ 临时 PNG → share_plus。

### 健壮性
- 聚合整体 try/catch，失败显示 `_ErrorView`（SelectableText 异常+堆栈）+ 重试按钮
- 空年份显示 `_EmptyYear` 引导，不再是干瘪一行字
- 所有照片位带 `File.existsSync()` 预检 + errorBuilder，**丢图不会崩**

### 本轮踩的坑（analyze 首轮报 19 项）
1. **`getAllTrips()` 返回 drift 行对象**，没有 `durationDays`（那是模型的派生 getter）
   → 加 `_toModel()` 逐字段映射。**这是本项目的老陷阱**：DAO 返回 db.Trip，
   凡用模型属性必须先映射（trip_provider 里已有同样写法）
2. `'..._${_selectedYear}_$_page_...'` —— `$_page_` 被解析成标识符 `_page_` → 必须写 `${_page}`
3. `Navigator.pushNamed(context, ...)` 写在**无 context 的私有方法**里 → 给 `_trip()` 加 BuildContext 参数
4. **`Trip.rating` 是非空 int（默认 0）**，`rating != null` 恒真、`rating!` 无效、
   `a.rating ?? 0` 是死代码 → 全部改为 `rating > 0` / 直接比较。
   顺带修正原页面"最佳旅程"实为"最长旅程"的语义错误
5. 封面卡里遗留一行 `Text('$d'.replaceAll(...), height: 0)` 垃圾代码 → 删
6. 未用 import（mood_type）+ prefer_is_empty 各一处

---

## 🎨 第二十三轮：精灵改为 3D 观感造型（四套皮肤，20:58 包，已安装）
最新 release：`build\app\outputs\flutter-apk\app-release.apk`（47.1MB，10-11 20:58）√ Built，analyze 零错误
`adb install -r` → Success。

用户给四张 3D 渲染图（豆包生成），要求把 AI 形象做成这种 3D 风格。

### 造型语言提炼（四图共性）
大头小身（约 6:4 chibi）· **脸是一块圆润镜面屏** · 全身径向渐变体积感 ·
边缘轮廓光 · 虹彩半透明翅膀 · 胸口发光核心 · 下方柔影悬浮 · 头顶高光斑

### 诚实说明的限制（已告知用户）
CustomPaint **做不到真 3D**（无透视旋转、无真实光照模型）。
采用「多层径向渐变 + 高光条 + 轮廓光 + 半透明虹彩翅膀」模拟柔和立体渲染，
在 60~90px 悬浮尺寸下观感接近，且保持零图片资源、跟随主题、深色自适应、表情可逐帧变化。
（参考图带"豆包AI生成"水印，也不能直接当素材用）

### 改动
- `models/sprite_form.dart` **重写**：旧的 cloud/plane/compass 三个手绘形象**整体替换**为
  angel小羽/bubble小泡/cosmic小星/travel小旅 四款；`fallback` 改为 travel。
  旧 prefs 里存的 'cloud' 等 key 经 `fromKey` 找不到会安全回落到 travel。
- 新增 `widgets/sprite/sprite_skin.dart`：`SpriteSkin`（外壳三段色/轮廓光/镜面上下色/眼色/
  核心色/翅膀三色 + 配件开关 wings·halo·antenna·camera·backpack·starfield·circuits·chip·
  glassHead·earDisc·blush）+ **8 套预设**（4 形象 × 明暗各一）。
  绘制器只认 Skin，加第 5 款只需再加一个预设。
- `sprite_painter.dart` **完全重写**为通用机器人绘制器：
  `_sphere()` 径向渐变球（受光点偏左上）· `_groundShadow()` 径向柔影（非实心椭圆）·
  `_head()` 实心壳或玻璃穹顶 · `_visor()` 圆角镜面屏（上下渐变+底部内发光+斜高光条，clipRRect 内画）·
  `_glossyEyes()` 大眼+双高光点做玻璃珠质感 · `_wings()` 泪滴形虹彩渐变+白描边+翅脉+拍翅角速度 ·
  `_chestCore()` 外发光+环+内芯三层 · `_halo()` 双描边椭圆光环 · `_antenna()` 杆+发光球+四角星 ·
  `_starfield()` 黄金角分布闪烁点 · `_circuits()` 金色电路纹 · `_camera()` 机身+镜头渐变+高光 ·
  `_chip()` 芯片+四边引脚+金框+"AI"文字 · `_rimLight()` 头部右下渐变轮廓光
- 表情系统迁移到**镜面屏上**（比原来的白脸更合适）：happy 弯月眼 / dragging `> <` /
  sleepy 闭眼+飘z / thinking 眼珠上瞟+头顶弧圈 / speaking 口型随时间开合 / idle 眨眼
- `travel_sprite.dart`：改为传 `skin: SpriteSkins.of(form, dark:)`，删除 body/accent/ink 三参数与无用 colorScheme

### 本轮自查修掉的问题
1. `_straps` 里误输入**天城文字符** `0xFF8D6E४F` → 该变量本就是死代码，整行删除
2. `SpriteForm.cloud` 已不存在导致 `const SpritePrefs()` 连带报 2 个错 → 默认值改 travel
3. 腮红循环用嵌套 List + 多余 cast → 改为直接遍历 x 坐标列表
4. `_visor` 里遗留无意义 `c.rotate(0)`；`_wings` 里冗余 `.shift(Offset(0,0))` → 删
5. `travel_sprite` 的 `cs` 变量随参数变更变为未用 → 删

### 真机验证情况
- `adb install -r` → **Success**，包时间戳晚于全部源码
- 截图受阻：手机**连续自动锁屏**（8:58 / 9:01 两次截到锁屏），中间一张截到
  **解锁过渡的模糊态**，但可辨认精灵已渲染（设置页右侧出现蓝紫色带尾翼形状，
  且设置页可见「旅行精灵」开关为开、底部形象胶囊区已换成新四款）
- **未能拿到清晰定妆照** → 实际观感需用户自己看；不再反复尝试解锁（不应绕过锁屏）

---

## 🔧 第二十二轮：精灵三处修复 + FAB 重叠（20:45 包，**已 adb 安装并截图验证**）
最新 release：`build\app\outputs\flutter-apk\app-release.apk`（47.0MB，10-11 20:45）√ Built，analyze 零错误

用户反馈：① 记账确认卡里**不能选择行程** ② **没看到语音怎么用** ③ 要求**小窗可拖拽移动**。

### ① 行程选择：DropdownButtonFormField → ChoiceChip 横排
下拉弹层在 306 宽的小窗里容易被裁切/难以点中。改为**横向滚动的旅程胶囊**：
一眼可见全部旅程、点一下即选中（选中带勾 + 分类主色描边加粗）。
顺带把 `_pendingCard` 的 `List<dynamic>` + `(t as dynamic).id` 改成**强类型 `List<Trip>`**（补 trip_model import）。
trips 为空时显示红字提示"还没有旅程，先建一段才能记账"，而不是静默不渲染选择区。

### ② 语音：从"不可用就隐藏"改为"始终可见 + 点击给说明"
之前不可用时**不渲染麦克风按钮**，结果用户根本找不到语音入口（正是这次的反馈）。
改为：
- 麦克风**恒显示**；不可用时图标 `mic_off` + 灰色 + tooltip「本机没有可用的语音识别」
- 可用时 tooltip 直接教用法：**「按住说一笔，比如『午餐四十五』」**
- 不可用时点击 → SnackBar 明确给替代路径：「点输入框后，用键盘上的麦克风也能说话」
- 正在听时图标变红 + tooltip「正在听…再点一下结束」

### ③ 小窗可拖拽
`SpriteBubble` 新增 `onDragStart/onDragUpdate`，**整条标题栏**为拖拽区（含 `drag_indicator` 把手图标 + tooltip 提示），
按钮点击不受影响（pan 与 tap 手势可共存）。
`SpriteOverlay` 侧：`_bubblePos`（null=跟随精灵自动摆放）、`_clampBubble` 限制在安全区内、
`_bubbleDragStart` 先把自动位置固化避免跳位、**每次重新打开对话窗重置为跟随精灵**。

### ④ 真机截图发现的新缺陷（已修）：精灵压住 FAB
截图显示纸飞机正好叠在「新建旅程」按钮上——**这正是我在方案里承诺要避免的"挡内容"**。
根因：`_clamp()` 底部只留了 `padding.bottom + 76`，没算 FAB 的高度。
改为 `padding.bottom + 150`（同时避开导航栏与右下角 FAB），默认初始位置也抬高。
存量偏好位置会在 `_initPosition → _clamp()` 时被**自动拉出 FAB 区**（自愈，无需清数据）。
**复验截图确认**：精灵已移到 FAB 上方，间距清晰。

### 真机验证结果
- ✅ 旅程**正序**生效：泰安2024-07 → 济阳 → 济南 → 烟台2025 → 石家庄 → 洛阳2026-10
- ✅ 精灵渲染正常（纸飞机形态：白机身 + 双眼 + 微笑 + 尾迹虚线），说明用户已自行换过形象
- ✅ 泰安/石家庄封面照片已被用户重新添加，显示正常
- ✅ App 进程存活，crash 缓冲区无记录
- ⚠️ MIUI 仍拦截 `adb shell input tap`，故 **行程胶囊点选、小窗拖拽、语音** 三项
  **只做了代码级修复，未能真机操作验证**，需用户实测

### 排查记录
`pidof` 首次返回空被误判为崩溃——实为 force-stop 与 monkey 抢跑；
改用 `am start` + 查 `topResumedActivity` + crash buffer 确认 App 正常。
日志里的 `AndroidRuntime` 行属于 monkey 自身进程（result code 0），非本应用。

---

## 🧚 第二十一轮：旅行精灵（可拖拽悬浮 AI 小助手，20:24 包，设备离线未装）
最新 release：`build\app\outputs\flutter-apk\app-release.apk`（47.1MB，10-24 20:24）√ Built，analyze 零错误

**用户决策**：三种形象都做且可切换；对话窗要"聊天 + 语音召唤 + 自然语言记账"；
全页面显示但**写日志时自动隐藏**。

### 为什么手绘而不是用网上的图/Lottie
- 版权：Behance/Envato 上的形象不能直接扒进 App 分发
- 依赖：Lottie 路线要加 lottie 依赖，本项目已三次踩依赖冲突（share_plus×drift、Kotlin 2.2 元数据）
- 手绘矢量额外收益：**跟随主题色与深色模式**、0 资源体积、任意尺寸不糊、
  **能与心情系统联动**（这是贴图做不到的）

### 新增文件
- `models/sprite_form.dart` — SpriteForm 枚举（cloud朵朵/plane飞飞/compass南南）+ SpriteMood 状态枚举
- `providers/sprite_provider.dart` — `spriteProvider`(偏好持久化到 settings 键 `sprite_prefs`)、
  `currentRouteProvider` + **`SpriteRouteObserver`**（跟踪路由以在编辑页隐藏）、
  `spriteVisibleProvider`、`spriteChatOpenProvider`。
  **位置存归一化坐标 nx/ny（0..1）**，换设备或转屏不会跑到屏幕外
- `widgets/sprite/sprite_painter.dart` — 三套形象 + 统一"表情语言"
  （眨眼每3.6s一次/弯月眼happy/`> <`dragging/闭眼sleepy+飘z z/眼睛上瞟thinking/口型随时间开合speaking）。
  云朵带草帽+背包+投影+挥手；纸飞机有尾迹虚线与倾斜机身；指南针指针随时间摆动（思考时加速）
- `widgets/sprite/travel_sprite.dart` — 约30fps AnimationController + Stopwatch 计时 +
  **AppLifecycleState 后台暂停** + 3分钟无互动自动打瞌睡（interactionTick 重置）
- `widgets/sprite/sprite_bubble.dart` — 306宽对话窗：头部小精灵头像、消息流、
  快捷指令、输入行、**记账确认卡**
- `widgets/sprite/sprite_overlay.dart` — 全局悬浮层：拖拽、**松手吸左/右边**、贴边折叠、
  单击开合、双击进全屏页、长按菜单（换形象/折叠/隐藏/全屏）
- `services/expense_intent.dart` — 中文记账短句解析

### 会话真正共享（不是两套记忆）
读写与 AiChatPage 相同的 settings 键 `ai_chat_sessions`，**更新第一条（最新会话）的 messages**，
消息格式 `{role, text}` 已核对源码一致。解析失败降级为空会话不影响使用。

### 自然语言记账（宁可少认，不可认错）
`ExpenseIntentParser.tryParse`：无明确金额返回 null 交回普通聊天；
分类关键词按具体度排序（"高铁"优先于泛化"票"）；
**取最后一个数字为金额**，避免"2个人 高铁320"把人数当金额；
识别出后**不直接入账**，先弹确认卡（分类/金额/备注/归属旅程下拉可改），用户点"确认入账"才写库。

### 语音：speech_to_text 7.4.0（pub get 成功，无冲突）
- AndroidManifest 加 `RECORD_AUDIO`
- **启动时 `_speech.initialize()` 探测可用性**，不可用则麦克风按钮根本不渲染
  （小米无 Google 服务时系统 SpeechRecognizer 可能缺失，不能让用户点了才报错）
- 失败额外给 SnackBar 提示"可点输入框用键盘的麦克风"——键盘语音是 100% 可靠兜底
- 识别结果经 `voiceText` + `onVoiceConsumed` 传入对话窗自动发出，
  避免用 GlobalKey 暴露私有 `_SpriteBubbleState`

### 本轮踩的坑（analyze 首轮报 16 项）
1. `canvas.drawCircle(cx, cy, r, paint)` → 签名是 `(Offset, radius, Paint)`，三处
2. `TextPainter.text = 'z'` 需 `TextSpan`；且 `textStyle` 不是 setter，只能构造时传
3. `AnimationController.elapsedInMilliseconds` **该版本不存在** → 改用 Stopwatch（与 MoodEffectLayer 同法）
4. `DropdownButtonFormField.initialValue` → 此 Flutter 版本叫 `value`
5. `NavigatorObserver` 重写方法参数名须与父类一致（`previousRoute`）
6. `SpriteForm` 没有 `emoji` 字段（我自己臆想的）
7. 对话窗打开时误把精灵渲染成 `SizedBox.shrink()` → 精灵会消失，改为始终显示
8. 删 import 的 edit 又差点弄坏结构；`_dragging`/`_micChecked` 冗余变量清理
9. `speech_to_text` 的 `localeId:` 已弃用 → 改 `listenOptions: SpeechListenOptions(localeId:)`

### 已知警告（判定为良性，不改）
Gradle 提示 `flutter_plugin_android_lifecycle requires Android NDK 27.0.12077973`，
项目用 `flutter.ndkVersion`（26.3.11579264，本机唯一已装）。该插件**无原生代码**，
声明的是其脚本默认值；强行改 27.0 会因本机未装该 NDK 而**彻底构建失败**。故保持现状。

**状态**：analyze 零错误、APK 已构建（20:24，47.1MB）。设备离线，**尚未安装**。

---

## 📅 第二十轮：首页旅程按时间排序（最终为**正序**，19:34 包，设备离线未装）

**根因**：`watchAllTrips()` / `getAllTrips()` **完全没有 orderBy** →
返回的是 SQLite 默认 rowid 顺序，也就是**创建先后**，所以看起来乱。
（实测截图印证：洛阳2026-10 / 石家庄2026-10 / 泰安2024-07 / 济阳2024-08 / 济南2024-08 / 烟台2025-05 —— 明显非日期序）

**修复**：在 SQL 层排序（而非 Dart 重排）。用户先要倒序，随即改口要**正序**
（最早的去过排前面，像日记从头翻）→ 两条查询均为 `orderBy(startDate ASC, id ASC)`，
同日按 id 正序保证顺序稳定。

### 连带修正（改排序方向引发的真实 bug）
`quick_add_sheet` 的默认旅程原先取 `trips.first`。provider 变正序后
**first 会是最早的旅程（2024 泰安）**，导致记一笔时默认挂到最旧旅程上 —— 错的。
改为按日期语义选取，不再依赖列表位置：
- `TripOption` 增加 `startDate/endDate` 与 `isOngoing` getter
- `_resolveTripId()`：优先「正在进行」的旅程（今天落在起止区间内，多个取最新），
  否则取 `startDate` 最大者
- 记账面板内的旅程**选择列表**单独按日期**倒序**展示（选最近/进行中的更顺手），
  与 provider 展示顺序（正序）刻意不同，已在注释注明

**核查过的下游**：
- `todayMemoryProvider` 自己 filter 后显式 `sort(startDate asc)`，不受影响
- `expenseStatsProvider` / `expense_list_page` 只用 id→名称映射，与顺序无关
- `year_review` / `stats` 按年份取用，不受影响

**状态**：analyze 零错误、APK 已构建（19:34，46.9MB）。`adb install` 时**设备离线**
（这台小米本会话反复掉线），故**尚未安装**，需重连后装。

**排序改动后的首页预期顺序（正序）**：
山东泰安 2024-07 → 济阳 2024-08-11 → 济南 2024-08-17 → 烟台 2025-05 → 河北石家庄 2026-10-06 → 河南洛阳 2026-10-16

---

## 💰 第十九轮：旅行消费记录与统计（新功能，19:04 包，已 adb 安装）
最新 release：`build\app\outputs\flutter-apk\app-release.apk`（46.9MB，10-11 19:04）√ Built，analyze 零错误

**用户决策**：方案全部通过；**只记旅行消费（tripId 必填）**；单一人民币。

### 数据层
- 新表 `expenses`：id / tripId(必填, 级联删除) / logId(可空, SET NULL) / category / **amountCents** / note / expenseDate / createdAt
- **金额存整数「分」**：SQLite REAL 是二进制浮点，累加上千笔会出现分位误差且难排查；
  存分则求和永远精确，仅输入/显示时与元互转（`Money.parseInput` / `Money.format`）
- `schemaVersion 2 → 3`，`onUpgrade` 加 `if (from < 3) await m.createTable(expenses)`
  （与 `if (from < 2)` 并列，1→3 与 2→3 两条路径都正确）
- 已重跑 build_runner（106 outputs）
- DAO：insert/update(**局部 write，不用 replace**)/delete/getAll/watchAll/byTrip/watchByTrip/
  getExpenseCount/getTripTotalCents
- 分类固定 8 类（交通/住宿/餐饮/门票/购物/娱乐/医疗/其他）：自建分类会把同类切碎，饼图失去意义

### 新增文件
- `models/expense_model.dart` — Expense + ExpenseCategory 枚举 + **Money 工具**(分↔元、千分位格式化)
- `services/expense_stats.dart` — `ExpenseStats.from()`：总额/本月/分类占比/近6月(补空档月)/
  旅程排行/有消费天数(日均分母)/最大单笔
- `widgets/charts/donut_chart.dart` — 手绘环形图（含空数据底环）
- `widgets/charts/bar_chart.dart` — 手绘柱状图 + `RankBars` 横向排行
- `widgets/expense/quick_add_sheet.dart` — 记账面板：**保存后不关闭只清金额**（连记几笔是高频场景），
  分类九宫格/旅程选择/日期/备注，错误内联提示
- `widgets/expense/trip_expense_strip.dart` — 旅程详情顶部消费条（总额+笔数+日均+大头分类）
- `pages/stats/expense_section.dart` — 统计页区块：总览四格 + 环形图带图例 + 月度柱状 + 旅程排行 + 空状态
- `pages/stats/expense_list_page.dart` — 明细页：按日分组带小计、左滑删除、下拉刷新、FAB

### 接线
- `stats_page` 插入 `ExpenseSection`（年度回顾与成就之间）
- `trip_detail_page` 插入 `TripExpenseStrip`
- **5 个海报模板全部加花费行**：`TripPosterData.totalCents` + `costLine` getter +
  共用 `PosterCostLine` 组件（未记账时返回 SizedBox.shrink 不占位）
- `export_service` 导出 `expenses` 数组（同时给 amountCents 与 amountYuan）

### 图表为何手绘不引 fl_chart
本项目吃过依赖冲突亏（share_plus 与 drift 打架、12.x 的 Kotlin 2.2 元数据 Flutter 3.29 读不了）。
环形/柱状图逻辑简单，CustomPaint 零依赖、零冲突风险、样式全可控，且已有 mood_painter 的成熟经验。

### 真机验证（手机已连 adb）
- 构建 → `adb install -r` → Success（19:04 包）
- force-stop 后重新拉起，**首页完整渲染出全部旅程** → 说明 DB 成功 open →
  **onUpgrade(2→3) 的 createTable(expenses) 已执行成功**（若失败会抛 DatabaseException 且首页空白）
- logcat 全程无 `no such table` / SqliteException / DatabaseException / FATAL
- ⚠️ **无法自动验证新 UI**：MIUI 拦截 `adb shell input tap`（点统计 tab、点旅程卡片均无反应），
  ExpenseSection 的实际渲染需用户手动确认
- **顺带得到照片丢失的视觉证据**：首页「河北石家庄」「山东泰安」封面显示为破图占位，
  而洛阳/济阳/济南/烟台正常 —— 正是 cache 目录被部分清空的特征，印证第十七轮的诊断

---

## 🎯 第十八轮：日志/旅程保存失败的真正根因 —— drift replace() 整行校验（18:33 包，已 adb 安装）
最新 release：`build\app\outputs\flutter-apk\app-release.apk`（46.7MB，10-11 18:33）√ Built，analyze 零错误
**本轮通过 adb 连接真机 + 用户截图拿到决定性证据，不再靠猜。**

### 根因（第十七轮加的 try/catch 弹窗终于把错误暴露出来了）
```
InvalidDataException: Sorry, LogsCompanion(... createdAt: Value.absent(), ...)
cannot be used for that because:
• createdAt: This value was required, but isn't present
#1 UpdateStatement.replace (package:drift/src/runtime/...)
```
**drift 的 `update(table).replace(companion)` 要求整行所有非默认列齐备**，
缺 `createdAt` 就直接抛异常 —— 所以**编辑日志和编辑旅程的保存从第一天起就 100% 失败**。
第十七轮加的 `_save` try/catch 弹窗是定位关键：之前异常被静默吞掉，表现为"点了没反应"。

### 修复：改用局部更新 `update()..where().write()`
`write()` 只写 companion 中 present 的列，不做整行校验 —— 这才是 drift 正确的部分更新 API。
- `AppDatabase.updateTrip(int id, TripsCompanion)` → 返回受影响行数 int
- `AppDatabase.updateLog(int id, LogsCompanion)` → 返回受影响行数 int
- id 改为**显式参数**（不走 companion.id）：避免 `Value<int>.value` 的可空性歧义，
  且 `presentValue` 在本项目 drift 版本中不存在（曾因此构建失败）
- 3 处调用点同步更新：`log_editor._save`、`log_provider.updateLog`、`trip_provider.updateTrip`
- 三处均检查 `changed == 0` 并抛 StateError，杜绝"保存了但什么都没写"

### 同时补齐的可观测性
- `trip_create_page._save` 也包 try/catch + 失败弹窗（SelectableText 显示异常与堆栈）+ `_saving` 防重复
- 之前只有 log_editor 有，trip 编辑页仍会静默失败

### 教训（写死在代码注释里）
`replace()` 只适用于**持有完整数据行对象**的场景（如 upsertFootprint 传 `Footprint(...)`、
achievements 传 `Achievement(...)`，那些是齐备的 DataClass，可以保留）。
凡是"只改几个字段"的场景，一律 `update()..where().write()`。

### 本轮踩的次生问题
把 `.value` 改成 `.presentValue` 时未确认该 getter 在当前 drift 版本存在 → 构建 FAILURE。
**幸好 adb install 装的是上一次成功的包（已含核心修复），但这是运气，不是流程**；
已回退为显式传 id 的写法并重新构建安装。

---

## 🚨 第十七轮：照片丢失根因（cache 路径）+ 胶片条空白 + 加载错误可视化（18:07 包）
最新 release：`build\app\outputs\flutter-apk\app-release.apk`（46.7MB，10-11 18:07）√ Built，analyze 零错误

用户报三件事：胶片条空白、洛阳/河北/泰安照片没了、日志编辑保存仍无响应。

### ① 照片丢失【根因已确定，是真实数据损失】
`image_picker` 返回的是**缓存目录**临时文件（`.../cache/image_picker/xxx.jpg`），
而代码把该路径**直接写进数据库**。Android 在空间紧张时会回收 cache，
**更致命的是覆盖安装 APK 会清空 cache** —— 本次会话重装了十几次，正是照片消失的原因。
数据库里 filePath 记录还在，磁盘文件已没了。

修复：新增 `services/image_storage.dart`
- `persist(sourcePath, {folder})` → 复制到 `getApplicationDocumentsDirectory()/<folder>/`
  后返回持久路径；失败退回原路径且不抛异常（不打断用户操作）
- `looksEphemeral(path)` 识别历史 cache 路径；`exists(path)` 判存活
- 分目录：`trip_photos` / `trip_covers` / `profile`
- 应用到 3 处：`log_editor._addPicked`(合并 gallery/camera)、`trip_create._pickImage`、
  `profile_edit._pickAvatar/_pickPhoto`
- **已丢的文件无法恢复**（只能重拍/重传）；此后新存的不再丢

### ② 胶片条空白：无界高度塌陷
卡片位于 `SingleChildScrollView` 内 → 高度不受限；`_strip()` 里
`Stack(fit: StackFit.expand)` 依赖父级给定高度，无界时塌成 0 → 整条胶片空白。
修复：外层 Container 显式 `height: frameH + 16`，内层 Row 包 `SizedBox(height: 150)`；
齿孔列也随之获得有界高度（`MainAxisAlignment.spaceEvenly` 同样需要有界）。
顺手核查其余 4 个模板：wave/editorial/polaroid/boarding 的照片位均已显式给高，无此问题。

### ③ 保存无响应：补上加载侧的可观测性
`_save` 已有 try/catch 却仍"无反应"，说明问题在**更早的 `_loadLog`**——
它原先没有任何错误处理：一旦 `getLogById` 抛异常（如列缺失），
`_imagePaths`/`_contentController` 都停留在空值，且 `_isLoading` 永不置 false。
修复：`_loadLog` 包 try/catch，新增 `_loadError` 字段，
body 优先渲染 `_errorView()`——**把异常原文和堆栈用 SelectableText 显示在屏幕上**，
用户可直接截图反馈；另给「仍然新建/编辑」按钮解除卡死。
（设备未连 adb，`adb devices` 为空，故采用"让 App 自曝错误"策略而非猜测。）

### 待用户回报
装上后若日志编辑仍异常，屏幕上会出现「日志加载失败」+ 具体异常文本 —— 据此定位根因。
怀疑方向：数据库迁移未生效导致 `no such column: mood_tag`。

---

## 🎨 第十六轮：分享海报改为 5 种可选模板（17:35 包）
最新 release：`build\app\outputs\flutter-apk\app-release.apk`（46.7MB，10-11 17:35）√ Built，analyze 零错误

用户要求"多做几种模板让用户选择"。做成**构图差异明显**的 5 种，不是换色。

### 文件结构（拆分，避免单文件深嵌套出错）
```
widgets/share/
  poster_data.dart          PosterTemplate 枚举(5) + TripPosterData（含 displayCaption/dateRange/notesExcerpt/extraPhotos）
  trip_poster_card.dart     仅做 switch 分发
  templates/
    poster_primitives.dart  PhotoSlot（无图渐变兜底）/ BottomScrim / SealStamp（红印章，多模板复用）
    wave_template.dart      ① 撕纸海报：大图+波浪撕纸边+38px大字+红印章（原第十五轮实现迁移至此）
    editorial_template.dart ② 极简杂志：白底大量留白/刊头 TRAVEL JOURNAL NO.xx/44px w300 细字地名/三图条/等宽数据行
    polaroid_template.dart  ③ 拍立得：斜纹桌面底 + -0.045 弧度立得相 + 两条半透明胶带 + 白边手写区地名
    boarding_template.dart  ④ 登机牌：深蓝航头 FROM→TO + 字段网格(日期/时长/城市/记录/影像/评分) + 虚线撕口+冲孔 + 票根条码
    film_template.dart      ⑤ 胶片条：深色底 + 两侧 7 个齿孔 + 三格画面 + 琥珀色"N DAYS"标签 + ISO 400
```

### 新增能力
- 分享页顶部加**模板选择条**（横向 ChoiceChip 5 个，emoji+名称）
- **记住上次选择**：settings 键 `share_poster_template`，`_restoreTemplate()` 读、`_chooseTemplate()` 写
- 条码 `BarcodeStrip` 用目的地 hashCode 作 Random 种子 → 同旅程每次一致
- 心情粒子层在 wave/polaroid 模板中仍压在文字下方，且被各自轮廓裁剪（wave 用 WaveClipper）
- **登机牌模板刻意不放照片**（真实登机牌没有大图），改用字段网格 + 条码，形成差异

### 本轮踩的坑（analyze 首轮报 14 项，全部为 import/编辑事故，非逻辑错误）
1. 新文件忘 import material → StatelessWidget/Widget/Color 全未定义（poster_data、trip_poster_card）
2. 删 import 的 edit 误删换行，导致注释与 `class BoardingTemplate...` 挤成一行 → 类声明失效连锁 13 个错误
   **教训：用 edit 删某一行时，old_string 必须包含该行完整文本+其后换行，不能只删前后空白**
3. `MoodOverlay` 类不存在（臆想的抽象）→ 改为直接用 MoodEffectLayer
4. `_moodLayer(Clipper clip)` 占位方法引用了不存在的 Clipper 类型 → 删除
5. 三处 unused import（mood_type ×2、poster_primitives ×1）

---

## 🖼 第十五轮：旅程分享卡改为竖版旅行海报（17:25 包）
最新 release：`build\app\outputs\flutter-apk\app-release.apk`（46.7MB，10-11 17:25）√ Built，analyze 零错误

用户给了一张西藏旅游海报参考图，要求"精美 + 信息更多"。原分享卡只有 图标+地名+日期+天数，确实过素。

### 新增 `widgets/share/trip_poster_card.dart`
- `TripPosterData`：卡片所需全部数据由分享页聚合后传入（卡片自身不查库，便于预览与截图共用）
- `_WaveClipper`：`ClipPath` 画**底部波浪撕纸边**（quadraticBezier 交替上下控制点，5 段波，
  基线在 92% 高度处）；再叠一层同形状下移 5px 的半透明黑 → 撕纸投影
- 结构：主图区 250 高（照片/无图时绿渐变兜底）+ 顶部压暗文案 + 底部压暗大标题(38px w900 ShaderMask)
  + **红色竖排印章**（地名首 2 字，-0.10 弧度旋转 + 白描边，模拟盖章）
- 下半：notes 摘录引号体 → 3 张小图条 + "+N 张" → 数据带(天/城/篇/张) → 标签chips+星级 → TrailMate 水印
- 心情粒子层同样被 wave 裁剪，压在文字下

### 数据聚合（新增两个 DB 查询）
- `getImagesByTrip(tripId)`：`select(images).join([innerJoin(logs, logs.id.equalsExp(images.logId))])`
- `getCitiesByTrip(tripId)`：locations join logs，取 cityName 去重
- 主图优先旅程封面 coverPath，其余按时间补；`stripPhotos` 取末尾 3 张

### 分享页 `share_card_page.dart` 重写
- `_load()` 一次聚合 trip/logs/images/tags/cities/moods
- **新增可编辑文案输入框**（≤24字，留空用默认「用 脚 步 丈 量 世 界」），印在海报顶部，
  分享时的 text 也优先用它
- 保留心情特效选择条（无 / 旅程出现过的心情 / 其余）
- 注意：`db.getTripById` 返回 **drift 行对象**，不能直接赋给模型 `Trip?`，需逐字段映射

### 本轮自查修掉的问题（初版 analyze 报 8 处）
1. `CustomClipper` 里误写 `@override Path getSize(Size)` —— 该方法不存在，删除
2. `cs_green(int)` 返回 `List<Color>` 却当 `Color` 用 → 改两个 `static const` 色值
3. 主图 Stack 里 `_photo()` 重复渲染两次（图层顺序写错）→ 改为 阴影层→照片→粒子→遮罩→文字
4. 标签 Row 括号数错导致后续整段语法崩（`Expected to find ']'` 等 6 个连锁错误）
   → 提取 `_chips()` / `_stars()` 辅助方法，不再手堆嵌套
5. 漏 import `mood_effect_layer` → 补
6. `dart:math` 未使用 + `_WaveClipper` 可选参数从未传值 → 改为无参 const + 静态常量
7. 分享页 `trip_provider` import 变无用 → 删除

---

## 🔧 第十四轮：日志保存改为可诊断 + 档案卡配色自选（16:33 包）
最新 release：`build\app\outputs\flutter-apk\app-release.apk`（46.6MB，10-11 16:33）√ Built，analyze 零错误
（注意：本轮改动源码写于 15:11–15:33，但当时的构建作业 pwsh-33 因会话切换丢失、**从未产出**；
16:33 重新构建才真正进包。教训：构建作业 id 跨会话会失效，必须核对 APK 时间戳是否晚于源码改动。）

### 日志保存：用户反馈 14:41 包仍"不能保存"，说明上轮修的不是根因
本轮不再猜，改为**让失败可见**：
1. `_save()` 整体包 try/catch，异常时弹 AlertDialog 显示 `$e` + 堆栈
   （此前任何 await 抛异常都会静默中断 → 表现为"点了保存没反应"）
2. 新增 `_saving` 状态：保存中按钮置灰显示转圈，防重复提交，也让用户知道有在处理
3. **堵掉一个完全静默的失败路径**：`update(logs).replace()` 在 id 不匹配时只返回 false、
   **不抛异常** → 数据一条没写却毫无提示。把 `AppDatabase.updateLog` 返回类型改为 `Future<bool>`，
   调用方检查，false 时主动 `throw StateError('未找到要更新的日志…')`
4. 待用户回报弹窗里的真实错误信息，才能定位根因（怀疑方向：数据库迁移未生效导致
   `no such column: mood_tag`；或编辑入口传入的 logId 有误）

### 档案卡配色自选（用户要求）
- 新建 `models/card_style.dart`：`CardStyle` 枚举 5 套配色，每套含
  bandTop/bandBottom/bodyTop/bodyBottom/ink/inkSoft + `fromKey` 容错回退 green
  · 🟢永居绿 🔵护照蓝 🔴登机红 ️头等黑金 夜航紫
- `Profile` 新增 `cardStyle`（存 key，toJson/fromJson/copyWith 已同步）+ `style` getter
- `profile_card.dart` 重写：原 `static const` 颜色改为 `profile.style` 的实例 getter，
  相关 `const TextStyle/BoxDecoration` 全部去 const
- 编辑页新增「卡片配色」区块：5 个迷你卡面色板（上带下底渐变 + 选中打勾），Wrap 排列
- 右下徽标仍用 App 自有 explore 图标，**不放国徽/国旗**

### 追加：证件签发信息（用户要求"加一个"）
- `Profile` 新增 `issueAuthority`(String?) + `validUntil`(DateTime?)，含 toJson/fromJson/copyWith
  - `displayAuthority` getter：留空回落默认「旅行管理局」
  - `displayValidity` getter：null 显示「长期」，否则 `YYYY.MM.DD`
- 卡面在统计条与 MRZ 之间插入 `_issueRow()`：左「签发机关 X」右「有效期限 Y」，仿身份证底部一对字段
- 编辑页新增「证件签发信息」区块：签发机关输入框（≤12字）+ 有效期日期选择
  - 注意：有效期是**未来**日期，`firstDate: now, lastDate: 2099`；
    而「旅行起点」是过去日期（`lastDate: now`）——两者方向相反，不能复用同一个 picker
  - 可点 X 改回「长期」
- 最终 release 46.7MB / 16:44，analyze 零错误，已核对包时间戳晚于全部源码

---

## 🐞+🪪 第十三轮：日志保存两个真 bug + 档案卡改证件样式 + 特效增强（14:41 包）
最新 release：`build\app\outputs\flutter-apk\app-release.apk`（46.6MB，10-11 14:41）√ Built，analyze 零错误

### 修掉的两个 bug（用户报"日志编辑保存不成功"）
1. **编辑日志时新增/删除的照片被静默丢弃**：图片插入循环只写在 `else`(新建) 分支里，编辑分支根本不执行。
   → 新增 `AppDatabase.syncLogImages(logId, paths)`：删除已移除的、插入新增的、纠正 orderIndex；
     两分支统一在 if/else 之后调用。另加 `getImagesByLogOrdered`、`setImageOrder`（只改顺序，
     不覆盖 aiDescription/坐标）。`_loadLog` 改用 ordered 版本。
2. **详情页显示旧内容**：`logByIdProvider` 是 FutureProvider 有缓存，保存后从未失效 →
   返回详情页看到旧数据；而时间线用 StreamProvider 会自动刷新，两者不一致更让人以为没保存。
   → 保存成功后 `ref.invalidate(logByIdProvider(savedLogId))`。
   **同类问题一并修**：`tripByIdProvider` 在旅程编辑保存后同样陈旧 → 加 invalidate。

### 档案卡改为证件/永居卡样式（按用户给的参考图）
`widgets/profile/profile_card.dart` 全量重写，340 宽：
- 顶部深绿标题带：`TRAVEL RESIDENT CARD` 字距拉开 + 「旅行永久居留证」
- 左侧 82×106 竖版**证件照**（未上传显示占位提示）
- 右侧登记字段：姓名 NAME / 常驻 RESIDENCE / 旅行 SINCE(第N天) / 风格 chips / 斜体签名
- 中部 5 格统计条（城市/旅程/天数/照片/成就，竖线分隔）
- 底部 **MRZ 机读码**两行等宽字体，由昵称+统计确定性生成（`I<CN<<TRAVEL<<NAME`）
- 右下圆形 explore 徽标——**刻意用自有标识，不放国徽/国旗**，避免仿真实证件
- 配色：绿系证件渐变；心情特效层仍在文字下方，会被截进分享图

### 证件照与头像彻底分开
`Profile` 新增 `photoPath`（toJson/fromJson/copyWith 已同步）；编辑页顶部两个独立上传按钮
（圆形头像 / 竖版证件照）+ 证件照缩略图。JSON 存储无需迁移，老档案读出 null 正常降级。

### 特效增强（保留淡雅基调）
- 新增 `_applyTint`：每种心情一层极淡氛围色渐变（夜/星/烟花 deep 档稍强）
- 新增 `_depth(p)` 景深：远处小而慢淡、近处大而快亮
- rain 46→64（粗细/速度/透明度随景深）、snow 30→44（近处画六角）、
  petal 20→30（双层色差）、star 26→36、leaf 14→20
- 烟花改主束+半周期副束（提取 `_burst` 复用），连续绽放感
- 粒子上限 48→72

---

## 👤 第十二轮：个人旅行档案 + 档案卡片（新功能，13:56 包）
最新 release：`build\app\outputs\flutter-apk\app-release.apk`（46.6MB，10-11 13:56）√ Built，analyze 零错误

**用户决策**：8 字段全做；入口只放设置页顶部；卡片要带可自选的心情特效

### 存储取舍（重要）
**未新建数据表**，档案以 JSON 存于现有 `settings` 表的 `user_profile` 键。
理由：档案是单条记录、无查询需求，而建表要 v2→v3 迁移——v2 迁移用户尚未在真机验证，
**不叠未测迁移**。用强类型 Profile 模型 + toJson/fromJson 兜住类型安全。

### 新增文件
- `models/profile_model.dart` — Profile(8字段) + `travelDays` 计算 + ProfileStats
- `providers/profile_provider.dart` — `profileProvider`(Notifier<Profile?>，读写 settings)
  + `profileStatsProvider`(FutureProvider，汇总城市/旅程/天数/照片/日志/成就)
- `widgets/profile/profile_card.dart` — 320 宽档案卡，Stack 内特效在文字下层，
  头像有图用图/无图取昵称首字，预览与分享截图共用同一实现
- `pages/profile/profile_edit_page.dart` — 表单：头像/昵称(必填)/城市/签名/
  风格多选(上限6)/心愿增删/起点日期/特效心情
- `pages/profile/profile_page.dart` — 空状态引导 + 卡片预览 + 分享 + 编辑 + 清空(带确认)

### 改动
- `app_database.dart`：新增 `getLogCount()`、`getAchievementCount()`
- `app_router.dart`：注册 `/profile`
- `settings_page.dart`：顶部插入 `_ProfileEntry` 卡（未创建显示引导文案）
- `export_service.dart`：JSON 导出新增 `profile` 字段（getSetting 异步，须先 await 再解码）

### 卡片布局（已实现）
头像+昵称+签名 → 常驻城市/旅行第N天 → 4格数据(城市/旅程/天数/照片)
→ 风格chips → 心愿清单 → 成就进度 → TrailMate 水印

---

## 🎨 第十一轮：心情标签 + 12 种粒子特效（新功能，13:10 包）
最新 release：`build\app\outputs\flutter-apk\app-release.apk`（46.5MB，10-11 13:10）√ Built，analyze 零错误

**用户决策**：方案整体通过；强度=淡雅克制；心情种类从 8 扩到 12（新增 🌈彩虹/🌊海浪/🎆烟花/🌫️迷雾）

### 核心概念
`weather`（客观天气）与 `moodTag`（主观心情）**独立并存**，允许「天气☀️晴 + 心情🌧️下雨」这种张力记录。

### 数据层
- `logs` 新增 `moodTag TEXT NULL`（存 MoodType.key，改名不影响历史数据）
- **schemaVersion 1 → 2**，`onUpgrade` 用 `m.addColumn(logs, logs.moodTag)`，老数据保留、旧记录该列 NULL
- 已重跑 build_runner（126 outputs）
- `models/log_model.dart`：加 `moodTag` 字段 + `mood` getter；copyWith 用 `_unset` 哨兵区分"保持"与"显式置空"

### 新增文件
- `models/mood_type.dart` — 12 种枚举 + 元数据(key/label/emoji/accent/effectHint) + `fromKey`
- `widgets/mood/mood_painter.dart` — 12 种粒子 `CustomPainter`，**完全无状态**（只依赖 t 与粒子表）；
  不用 saveLayer/MaskFilter.blur，发光一律用 RadialGradient → 低端机友好
- `widgets/mood/mood_effect_layer.dart` — 动画容器：约30fps、App后台自动暂停、
  尊重系统 disableAnimations 降级为静态、IgnorePointer 不拦手势
- `widgets/mood/mood_picker_sheet.dart` — 12宫格选择器 + 顶部实时预览；
  用 `MoodPickResult{confirmed,mood}` 区分「取消」与「主动清除」（修掉了两者都返回null的歧义bug）
- `providers/settings_provider.dart` — `effectsProvider`（持久化开关）+ `effectsActiveProvider`（开关 && 系统未要求减弱动效）

### 渲染位置（按方案）
- 详情页：`Stack` 背景特效层（正文在上滚动，特效固定），头部加心情徽章
- 编辑器：写作区 Stack 背景实时预览；底部工具栏新增心情按钮（天气旁）
- 时间线：**静态**徽章（日头 emoji + 卡片左上角标签），不跑动画避免多卡掉帧
- 设置页：「日志心情特效」开关，副标题提示是否受系统减弱动效影响

### 实施中自查修掉的问题
1. `_paintSnow` 误用类字段 `late double fall` 当临时变量 → 改局部变量
2. `log.mood` 在编辑器里不存在（那里是 drift 的 db.Log 行对象）→ 改 `MoodType.fromKey(log.moodTag)`
3. MoodPicker 取消/清除返回值歧义 → 引入 MoodPickResult
4. settings_provider 多余 material import → 删除

### ✅ 已补齐（13:20 包）：分享卡片带特效
- 特效层放进 `RepaintBoundary` **内部**（Container > Stack > [MoodEffectLayer, Padding(内容)]），
  特效先绘制在文字下方 → 既被截进 PNG，又不影响文字可读性
- Container 加 `clipBehavior: Clip.antiAlias`，特效不溢出圆角
- 新增底部「卡片特效」选择条：`无特效` + 该旅程出现过的心情（横向滚动）+ 其余 12 种心情
- 默认预选「最近一篇有心情标签的日志」的心情（`_loadMoods` 按 date 倒序取第一个非空）
- 分享页为旅程级，故用 `tripId*17+11` 作粒子种子，同旅程每次一致
- release：46.5MB，13:20，analyze 零错误

---

## 📸 第十轮：足迹悬浮照片卡（新功能，12:45 包）
最新 release：`build\app\outputs\flutter-apk\app-release.apk`（46.4MB，10-11 12:45）√ Built，analyze 零错误

**需求**：点足迹里去过的城市 → 悬浮动态展示该地照片。用户已确认两个设计决策：
- 选取策略 = **最近3条日志各取首图**（跨旅程、全局按日志日期倒序），避免同一篇连拍刷屏
- 形态 = **底部浮卡 + 自动轮播**

实现：
1. `app_database.dart` 新增 `getRecentCoverImagesByCity(cityName, {limit=3})`：
   城市→trips(目的地文本匹配)→汇总所有 logs→**全局按 log.date 倒序**(同日按 createdAt 倒序)
   →逐条取该日志第1张(orderIndex asc, id asc) 直到凑满 limit
2. 新组件 `widgets/city_photo_float_card.dart`：PageView(viewportFraction .82) + Timer 2.6s 自动轮播循环、
   当前页放大两侧缩小、指示点、点击全屏预览(InteractiveViewer)、空态提示、loading 态、「查看该城市详情」按钮
3. `footprint_map_page.dart`：新增 `_floatCity/_floatPhotos/_floatLoading`；
   **点标记行为改变**：原来直接弹底部详情 sheet → 现在改为弹悬浮照片卡（详情通过卡内按钮进入）
4. 顺带修两个渲染 bug：
   - **高亮残留**：原代码只清被点城市的缓存，上一个选中项会一直红 → 位图缓存改为
     `_cacheKey(city, selected)` 分键，蓝/红两版共存，切换时上一个自然回蓝
   - **标记闪烁**：原先清空全部缓存重建期间所有标记会消失 → 分键后不清缓存，且选中版位图
     未就绪时回退用普通版占位，标记不再消失
5. 注意：`Positioned` 必须是 Stack 直接子节点，故 AnimatedSwitcher 放在 Positioned 内部而非反过来

### 交互说明（给用户）
点城市标记 → 底部滑入照片卡，3张图自动轮播（可手动左右滑、点图全屏查看）→
点「查看该城市详情」进原来的详情弹窗；点卡右上角 X 关闭并取消高亮。

---

## 🔑 第九轮：换新 AI Key + 修旅程编辑保存 + AI新建会话退出（12:19 包）
最新 release：`build\app\outputs\flutter-apk\app-release.apk`（46.4MB，10-11 12:19）√ Built，analyze 零错误

1. **AI Key 更换**（用户提供，旧 Key 已 401 Invalid API-key）
   - `api_constants.dart` → `hardcodedApiKey` 换成 `sk-ws-H.PEYHIPP.RURl...`
   - 实测：新 Key 在百炼端点 `qwen-flash` → HTTP 200 ✅
   - 临时探测脚本（含明文 Key）已删除，项目内无旧 Key 残留
2. **视觉模型修正**：该端点**没有** `qwen3-vl-flash`（404 Model not exist）→ 改为实测可用的 `qwen3-vl-plus`（生成测试图验证能正确描述）。可用视觉模型还有 qwen3.5-ocr / qwen-vl-ocr
3. **旅程编辑保存 bug（重要，之前只修了一半）**：`_loadTrip()` 回填了表单但 `_save()` 仍无条件 `createTrip()` → 编辑会变成**新建重复旅程**。已修：新增 `Trip? _editingTrip` 保存原记录，`_save()` 按 `widget.tripId != null` 分支走 `updateTrip()` + `setTripTags()`，提示文案区分「旅程已更新/已创建」
4. **AI 新建会话退出 bug**：`_newSession()` 里 `Navigator.pop` 原意关抽屉，但从 AppBar 按钮调用时无抽屉可关 → 直接退出对话页。已修为 `if (Scaffold.of(context).isDrawerOpen) Navigator.pop(context)`
   （注：此两项修复的代码在上一会话已写入，但当时构建作业 pwsh-2 因会话切换丢失，从未进包 → 本次才真正产出）

### 遗留可选项（未做）
- ⛔ **任意地名精确坐标（高德 Web服务 Key）—— 用户已明确决定不做，维持现状**
  - 现状：`geo_coder.dart` 离线库收录 **239** 个地名；`city_extractor.dart` 词表 国内84+海外51
  - 已知局限：目的地不在这 239 个里 → `_lightUpFootprint` 写入 (0,0) → 地图页
    `where(latitude != 0)` 过滤掉 → **该城市不会出现在足迹地图上**（列表页仍可见）
  - 曾评估的替代：A) 已集成的 `geocoding.locationFromAddress()` 正向编码（免费无需Key，
    但国产ROM无Google时精度不可控）；B) 高德"Web服务"类型 Key（最准，需另注册）。两者用户都选择暂不做。
  - 若日后要改：优先 A 做降级链（离线库→系统geocoder→0,0），仍不满足再上 B
- ⬜ release 用 debug 签名，分发需配正式 keystore
- ⬜ 自适应图标（adaptive icon）未做

---

## 🐛 第八轮：底部导航点足迹/统计/设置显示空白占位页（用户反馈截图）
最新 release：`build\app\outputs\flutter-apk\app-release.apk`（46.4MB，21:28）√ Built，analyze 零错误
- **根因**：home_page 的 IndexedStack 里放的是 `_PlaceholderPage`（图标+文字的假页面），真页面靠 onDestinationSelected 里 Navigator.pushNamed 打开 → 切 tab 看到占位空壳，push 返回后停在占位页
- **修复**：IndexedStack 直接内嵌真实页 `FootprintMapPage()/StatsPage()/SettingsPage()`；onDestinationSelected 只 setState 切 index 不再 push；删除 _PlaceholderPage 类；import 三个页面
- 三页各自带 Scaffold+AppBar，作为 tab 嵌入时 automaticallyImplyLeading 因 canPop=false 不显示返回箭头，正常
- AppRouter 仍保留这些路由（详情页等仍用），无冲突

---

## 🗺️ 第七轮：高德地图加回轨迹线+回放小人+所有城市显名（用户反馈：非省会没名字、轨迹被删了）
最新 release：`build\app\outputs\flutter-apk\app-release.apk`（46.4MB，21:19）√ Built，analyze 零错误
- **所有城市标记带名称**（不只省会）：footprint_map_page 用 Canvas+PictureRecorder 运行时绘制「彩色圆点(外发光+白边)+下方黑底白字城市名胶囊」位图，经 `BitmapDescriptor.fromBytes` 设为 marker.icon；_markerCache 按城市名缓存避免重绘；选中城市重绘为红色
- **发光轨迹线回来了**：AMapWidget.polylines 三层叠加——白 alpha40 w16 / alpha90 w8 / alpha230 w3，round cap/join，按 firstVisitedAt 升序连接（插入顺序）
- **回溯轨迹**：FAB「回溯轨迹」→ Timer.periodic 每40ms推进 _replayProgress(~6s走完)，🚶小人位图沿 _walkPoint(t) 逐段插值移动，相机 newLatLng 跟随；再点停止
- marker anchor (0.5,0.35) 让圆点对准坐标点；clickable=false 的小人 marker 不抢点击
- 注意：fromBytes 是同步 API，位图异步生成后 setState 刷新（首帧可能无名字，稍后即出）

---
## 🗺️ 第六轮：地图崩溃修复 + 手势缩放 + 城市坐标扩充 + AI预览交互
最新 release：`build\app\outputs\flutter-apk\app-release.apk`（46.4MB，20:xx）√ Built，flutter analyze 零错误
- **足迹闪退真因**（adb logcat 抓到）：`NoClassDefFoundError: com.amap.api.maps.AMapOptions` —— gmm_amap_flutter_map 用 `compileOnly` 引用高德库不打包进 APK。修复：app/build.gradle.kts 加 `implementation("com.amap.api:3dmap:8.1.0")`（阿里云/maven central 有）。包体积 28→46MB 即库真正打进去
- **双指不能缩放**：AMapWidget 加 `gestureRecognizers: {Factory(()=>EagerGestureRecognizer())}` 让原生地图独占手势；需 import flutter/foundation.dart(Factory)+gestures.dart
- **MainActivity 隐私初始化**：反射调用 MapsInitializer.updatePrivacyShow/Agree（高德类编译期对主模块不可见，用 Class.forName）
- **非省会城市不标记**：geo_coder.dart 离线词表从~90扩到300+（全国省会+地级市+景区+海外），lookup() 加后缀剥离(市县区州盟旗)和子串模糊匹配。⚠️ 仍非100%全，彻底解决需接高德 Web服务 geocode（用户当前 Key 是 Android 平台，调 restapi 返回 USERKEY_PLAT_NOMATCH，需另申请 Web服务 Key）——用户暂未要
- **AI 生成无预览**：ai_assist_bottom_sheet 写作/图片描述/每日总结改为「生成→_showPreview 可编辑弹窗→确认插入」，删掉旧的直接 _insertText 逻辑与死代码 _handleResult；按钮文案改「生成预览」「预览并编辑」
- adb 装包在小米上极不稳定（USER_RESTRICTED / 频繁掉线），用户决定自己传 APK 安装

---

## 🗺️ 第五轮：足迹地图换高德官方 SDK（用户选定）
最新 release：`build\app\outputs\flutter-apk\app-release.apk`（28.3MB，19:58）debug+release 均 √ Built
- 依赖：`gmm_amap_flutter_map ^3.1.4` + `gmm_amap_flutter_base ^3.1.4`（社区维护版，适配新 Flutter；官方 amap_flutter_map 已4年不更）
- AndroidManifest：加 com.amap.api.v2.apikey meta-data + 网络/WiFi/PhoneState 权限
- footprint_map_page 重写为 AMapWidget：可缩放平移、去掉轨迹线、城市 Marker（默认蓝色，选中变红高亮）、InfoWindow 显示城市名+到访次数、点击移动相机到该城并弹详情；隐私合规 privacyStatement 必须设 true
- R8 报错解决：android/app/proguard-amap.pro 加 -dontwarn/-keep com.amap.**，并在 build.gradle.kts release 配 proguardFiles（同时补了 proguard-rules.pro）
- NDK 版本警告（各插件要 27.0.12077973）非致命，Gradle 自动用最高版

## ⏳ 待用户提供高德 Key 后收尾
Key 占位在两处，拿到真实 Key 一起替换即可开箱：
1. lib/core/constants/amap_constants.dart → amapAndroidKey
2. android/app/src/main/AndroidManifest.xml → com.amap.api.v2.apikey 的 value
申请信息（我这边 debug keystore 提取）：
- 包名 Package name：com.trailmate.trailmate
- SHA1：EF:E4:9E:05:C2:8E:BA:7F:F2:01:0E:3C:AF:78:B0:C5:5A:DD:0D:C2
申请地址 https://console.amap.com/ → 创建应用 → 添加 Key(平台选 Android)
未填 Key 时足迹地图页显示「尚未配置高德地图 Key」提示页（不会崩）

## ✅ 高德 Key 已填入并打包完成（本次会话最新）
- Key `1f4bd4cf7e01dfbbe7cb670fa57dfc34` 已写入 amap_constants.dart + AndroidManifest.xml 两处
- release APK 重新构建 √ Built（28.3MB，20:04），flutter analyze 零错误
- 用户用调试版 SHA1 申请的 Key，对应 debug 签名；换正式签名需更新 SHA1

---

## 🔄 第四轮：足迹地图视觉升级（用户反馈：省份级底图/透明亮线/小人沿轨迹走/标记缩小）
最新 release：`build\app\outputs\flutter-apk\app-release.apk`（28.3MB，19:35）
- **中文省市注记**：ArcGIS 灰底 + 叠加 `World_Boundaries_and_Places` 注记层，通过 `NetworkTileProvider(headers:{Accept-Language:zh-CN})` 请求中文地名（无需 Key）。⚠️ 天地图(vec_w)无 key 返回 418、OSM 超时，故仍用 ArcGIS 双图层方案；若要更强中文可后续接天地图(需申请免费key)
- **透明发光亮线**：PolylineLayer 三层叠加——外晕(alpha45,w12)+柔光(alpha90,w6)+白芯(alpha220,w2)，圆角端点，悬浮发光感替代原实线
- **严格按添加顺序连线**：ordered 按 firstVisitedAt 升序，_visibleRoute/_routePoints 保持该顺序
- **回放小人**：新增 `_WalkerIcon`（directions_walk 走路图标+底部发光点），`_replayHeading()` 算行进朝向并 Transform.rotate 让小人朝前走
- **城市标记缩小**：图钉 46/34→26/20，标签字号 11→9，marker 尺寸 80→60
- flutter analyze 零错误

---

## 🔄 第三轮修复（用户反馈：地图仍灰/AI流式/多会话/建议无响应/评分点不动）
最新 release：`build\app\outputs\flutter-apk\app-release.apk`（28.2MB，17:37）
- **地图灰屏真因**：不是 PNG 解码（flutter_map 用 ImmutableBuffer+decode 格式无关）。高德瓦片服务器实测不拦 App。最终换 **ArcGIS World_Light_Gray_Base 瓦片**——WGS-84 坐标系与 GPS 一致（高德是 GCJ-02 火星坐标会有偏移），且无需 Key、国内可达。加了 fadeIn 过渡
- **AI 流式输出**：ai_service 新增 `chatStream()`（SSE，ResponseType.stream，逐行解析 data: 增量回调 onChunk）。对话页边收边填气泡，可点停止按钮 CancelToken 取消
- **AI 多会话**：改为 sessions 列表存 settings 表 `ai_chat_sessions`；左侧抽屉列出历史会话，可新建/切换/删除；标题取首条用户消息
- **推荐提问可点**：_Suggest 通过 findAncestorStateOfType 调 `_useSuggestion` → 填入输入框并直接发送（之前 onPressed 是空的）
- **评分星星可点**：trip_header 把 IconButton(零约束,点击区太小) 换成 InkWell + 28px图标 + 足够 padding + HapticFeedback；点第一颗星且已是1分时清零

---

## 🔄 第二轮修复（用户反馈：首页白屏/地图不亮/成就看不到条件/对话不保留）
最新 release：`build\app\outputs\flutter-apk\app-release.apk`（28.2MB，16:25）
- **首页白屏根因**：上次大图卡的 Stack 无封面时高度塌陷为0 → 整卡不可见。改为**时间轴风格**：新增 `widgets/timeline_row.dart`（左侧圆点+连线），trip_card 重写为「缩略图+文字」行卡，彻底不再有零高度问题
- **成就未解锁可查条件**：_LockedAchievementTile 包 InkWell，点击弹框显示描述+解锁条件
- **AI 对话持久化**：ai_chat_page 把消息存 settings 表 `ai_chat_history`（最近40条），initState 恢复；清空按钮同时清 DB
- **地图仍用高德瓦片**（webrd autonavi，实测能返回 png）。⚠️ 用户之前"地图空白"很可能是装了换瓦片之前的旧包——需装 16:25 这个新包验证
- **高德官方 SDK 暂缓**：amap_flutter_map 已4年不更新、依赖老SDK，Flutter3.29 上大概率编译失败且要申请Key+改原生工程，风险高。先看新包瓦片地图是否正常再决定要不要上 SDK

## ✅ APK 打包已跑通（本次会话）

## 🎨 界面美化 + 中文化 + 高德地图（本次会话续）
针对用户反馈"图不显示/界面丑/地图空白/英文"做了整体升级，重新打了 release（28.2MB）：
- **封面图修复**：trip_card 之前只画占位图标没渲染图片 → 改为真正 `Image.file` 铺满卡片 + 底部渐变遮罩 + 标题叠加的现代大图卡
- **全局中文化**：app.dart 加 `flutter_localizations` + `locale: zh_CN`；日期选择器、对话框按钮(确定/取消)不再英文。pubspec 加了 flutter_localizations
- **足迹地图换高德瓦片**：OSM 国内打不开→底图空白；改用 `webrd0{1-4}.is.autonavi.com/appmaptile?...style=8`（实测 HTTP200 image/png，中文标注秒开）
- **主题精修**：统一 softShadow() 柔和阴影、圆角升到 18-24、卡片去 elevation 用描边+渐变、导航栏/AppBar/FAB/对话框细节打磨
- **首页重构**：SliverAppBar 大标题「我的旅程」+副标题、FAB 改 extended「新建旅程」、空状态升级为圆形图标容器
- **统计卡片/城市图钉**：StatsCard 渐变+主色数字；图钉用 location_pin + 投影 + 圆角标签胶囊
- 注意：widget_test 断言从 'TrailMate' 改成 '我的旅程'（首页标题变了）

### 最终生效的构建配置（复现要点）
- Gradle：wrapper 指向本地文件 `file:/.../\_gradle-8.10.2-bin.zip`（腾讯云镜像下载，绕开 services.gradle.org 超时）
- AGP `8.7.0` + Kotlin 插件 `1.9.24`（settings.gradle.kts）
- JDK：gradle.properties 里 `org.gradle.java.home=C:\\Users\\32229\\.jdks\\ms-17.0.17`（避开 Java 25 与 AGP 不兼容）
- Maven 仓库：settings/build.gradle.kts 加了阿里云 google/public/gradle-plugin 镜像
- AndroidManifest：删掉 package 属性、activity theme 用 @style/LaunchTheme
- **share_plus 降到 `^10.1.4`**（关键！12.x 要 Kotlin 2.x，Flutter 3.29 不支持）；分享 API 相应回退为 `Share.shareXFiles([...], text:, subject:)` / `Share.share(text)`（见 share_service.dart、share_card_page.dart）
- 首次构建会自动装 SDK Platform 34（约 18 分钟），之后增量 ~2 分钟
- 注：构建尾部有 Kotlin daemon 堆栈噪声，但属非致命，APK 正常产出

### 下一步可选优化
- ⬜ release 包体积大→可加 `--split-per-abi` 或配 R8 混淆瘦身
- ⬜ debug 包签名是默认 debug key；要分发需配 release signing
- ⬜ 图标目前只有 ic_launcher 方图；如需自适应图标(adaptive icon)再补 foreground/background

## 🟢 最新状态（本次会话）
`flutter analyze` → **No issues found!**（全项目零错误/警告/info）。
**Phase 1 / 2 / 3 / 4 全部完成，且所有外部接口均已实测连通。**

### 天气自动获取（已完成并实测 ✅）
- 和风天气 QWeather，Key/Host 写死在 `weather_constants.dart`（App 开箱即用）
- Host: `ma3h2tx36p.re.qweatherapi.com`；认证用 v7 `/v7/weather/now?location=lon,lat&key=` （该 Key 是旧版鉴权，Bearer/JWT 会 401）
- 日志编辑器定位成功后自动查天气填入；condition icon→类别映射已按官方码表校正
- 设置页「🌤️ 天气服务」入口：仅当常量未填时才显示（现已隐藏，普通用户看不到）

### AI 功能已接入真实接口并实测连通（阿里云百炼 OpenAI 兼容模式）
- Base URL: `https://ws-fqns0gni8kjy6u4t.cn-beijing.maas.aliyuncs.com/compatible-mode/v1`
- 文本模型 `qwen-flash`（写作/标签/总结/对话）—— 已测通 ✅
- 视觉模型 `qwen3-vl-flash`（图片描述）—— 已测通 ✅
- 默认值写在 `api_constants.dart`；API Key 由用户在「设置→AI」填入（不落代码库）。
- 设置页新增「视觉模型」字段；`api_vision_model` 存 settings 表。

### 本次新增文件
- `lib/services/export_service.dart` —— JSON / Markdown / PDF 导出（含 `exportServiceProvider`）
- `lib/pages/chat/ai_chat_page.dart` —— 2.8 AI 多轮对话助手（路由 `/chat/ai`，首页工具栏入口）
- `lib/services/weather_service.dart` —— 天气服务 + WeatherFetcher（实时天气）
- `lib/core/constants/weather_constants.dart` —— 天气 Key/Host 常量

### 剩余待办（下次继续）
- ✅ AI Key 也已写死常量（`hardcodedApiKey` in api_constants.dart），实测连通；设置页 AI/天气入口在写死后自动隐藏，普通用户看不到 → **全部开箱即用**
- ✅ 应用图标已生成（柔和青蓝渐变圆角方块 + 白色定位图钉 + 旅行轨迹线，5 个密度全覆盖）
- ✅ 日志详情页展示 GPS 位置（城市·地点 + 坐标，点击跳足迹地图）
- ✅ 天气自动获取

---
- `app_database.dart`：新增 `getTripsByCity()`、`upsertLocationForLog()`、`findOrCreateTag()`、`appendTripTags()`
- `log_editor_page.dart`：接 `location_service`，定位按钮真正获取坐标+反查城市，保存时写 locations 表；顶部显示可删除的定位 Chip
- `city_detail_sheet.dart`：改为 ConsumerWidget，底部「相关旅程」列表可跳转详情
- `share_card_page.dart`：ConsumerStatefulWidget + GlobalKey(RepaintBoundary)，`toImage(pixelRatio:3)`→PNG→`SharePlus.instance.share(ShareParams(files:[XFile]))`
- `settings_page.dart`：导出三项接 ExportService；Markdown/PDF 先弹旅程选择器
- `ai_service.dart`：新增 `describeImage()`（多模态 base64）、`chatWithHistory()`（多轮）
- `ai_assist_bottom_sheet.dart`：图片描述 tab 真正选图+调用；标签 tab 支持「全部应用到旅程标签」落库（2.7）
- `footprint_map_page.dart`：3.7 轨迹回放——FAB 播放一个光点沿时间顺序逐段移动

---

## 0. 环境与命令备忘（重要）

- **Flutter SDK**：`E:\develop\Flutter SDK\flutter\bin`（3.29.2 stable，已永久写入用户 PATH）
- **国内镜像**（已设为用户环境变量）：
  - `PUB_HOSTED_URL = https://pub.flutter-io.cn`
  - `FLUTTER_STORAGE_BASE_URL = https://storage.flutter-io.cn`
- **项目目录**：`E:\ai-develop\AIcoding\Travel diary`
- **常用校验命令**（在普通 PowerShell 里跑，本会话沙箱也能跑 analyze）：
  ```powershell
  $env:Path += ";E:\develop\Flutter SDK\flutter\bin"
  cd "E:\ai-develop\AIcoding\Travel diary"
  flutter analyze            # 静态检查（当前应 0 error / 0 warning）
  dart run build_runner build --delete-conflicting-outputs   # 改了表结构后重新生成 .g.dart
  ```
- ⚠️ **打包 APK 在本机/本沙箱都卡在 Gradle**（联网下载超时 + 沙箱禁止写工作区外）。代码本身没问题，打包要在你正常终端用 Android Studio 出包，见文末。

---

## 1. 已完成 ✅

### Phase 1 核心功能（全部完成，analyze 零错误）
- 脚手架 + drift 数据库（9 张表 + `app_database.g.dart` 已生成）
- trips 表 + 创建旅程页、首页卡片列表、旅程详情+时间线
- 日志编辑器（图片/天气/AI辅助）、日志详情/编辑/删除
- 标签系统、搜索功能
- Material 3 + flex_color_scheme（5 套主题）、圆角 15px、空状态、下拉刷新

### Phase 2（部分完成）
- ✅ **2.1 足迹自动点亮**：新建 `utils/city_extractor.dart`（城市名提取词表）+ `utils/geo_coder.dart`（知名城市经纬度离线库）；`trip_provider.createTrip()` 保存旅程时调用 `_lightUpFootprint()` 写 footprints 表（已存在则 visitCount++）
- ✅ **2.2 足迹地图页**：flutter_map + 图钉 MarkerLayer + 列表视图
- ✅ **2.4 旅行轨迹连线**：按首次到访时间连 Polyline
- ✅ **2.5 AI Service 接真实 API**：重写 `services/ai_service.dart`，从 settings 表读 api_key/base_url/model；提供写作润色/智能标签/每日总结/测试连接；未配置优雅降级
- ✅ AI 辅助弹窗改为真正调用服务（`ai_assist_bottom_sheet.dart`）
- ✅ 设置页「测试连接」接到真实服务，带结果图标反馈

### Phase 3（部分完成）
- ✅ **3.1 统计看板**、**3.2 成就系统**（6 个成就 + 解锁检查）、**3.3 年度回顾** —— 这些是 Phase 1 阶段就建好的页面
- ✅ **3.4 今日回忆**：新增 `todayMemoryProvider`（历史上的今天），首页顶部插入 MemoryCard
- ✅ **3.5 深色模式 + 主题切换持久化**：`theme_provider.dart` 重写为 ThemeNotifier + ColorSchemeNotifier，变更写入 settings 表并在启动时恢复
- ✅ **3.6 城市点亮动画**：足迹地图标记按顺序错峰弹入（缩放+淡入），轨迹随动画显现

---

## 2. 待办 ⏭️（明天从这里开始）

### Phase 2 剩余
- ⬜ **2.3 城市详情弹窗增强**：`city_detail_sheet.dart` 目前只显示城市/国家/首访/次数，需补「关联旅程列表」（点进去跳旅程详情）。需要加一个按城市查旅程的查询方法。
- ⬜ **2.6 AI 图片描述**：多模态模型调用（describeImage，base64 传图），当前 UI 是占位提示
- ⬜ **2.7 AI 智能标签落库**：现在推荐标签只插入正文文本，未与 tags/trip_tags 表联动
- ⬜ **2.8 AI 本地对话助手**：独立聊天页（新页面）

### Phase 3 剩余
- ⬜ **3.7 轨迹回放动画**：沿 Polyline 逐段播放的动画（可在足迹地图加「回放」按钮）

### Phase 4（全部待做）
- ⬜ **4.1 分享卡片**：`share_card_page.dart` 已有卡片 UI，需补 RepaintBoundary 截图 + share_plus 真正分享
- ⬜ **4.2 JSON 导出**：settings 页「导出 JSON」目前是占位 toast，需实现全库导出到文件
- ⬜ **4.3 Markdown 导出**：选旅程→导出 md
- ⬜ **4.4 PDF 纪念册**：pdf/printing 包已在依赖里，未接入

### 收尾杂项
- ⬜ 应用图标/启动图仍是 Flutter 默认（打包前最好替换 `android/app/src/main/res/mipmap-*`）
- ⬜ 首页 AppBar 标题写死 "TrailMate"，可考虑跟随主题
- ⬜ GPS 定位按钮在日志编辑器里还是占位 toast，需接 `location_service.dart`（已写好但未接线）

---

## 3. 关键文件索引

| 作用 | 路径 |
|------|------|
| 数据库入口 + 所有 CRUD | `lib/database/app_database.dart` |
| 足迹点亮逻辑 | `lib/providers/trip_provider.dart`（`_lightUpFootprint`） |
| 城市名提取 | `lib/utils/city_extractor.dart` |
| 城市坐标离线库 | `lib/utils/geo_coder.dart` |
| AI 服务（真实调用） | `lib/services/ai_service.dart` |
| 主题持久化 | `lib/core/theme/theme_provider.dart` |
| 足迹地图+点亮动画+连线 | `lib/pages/footprint/footprint_map_page.dart` |
| 设置页（AI 配置/主题/导出） | `lib/pages/settings/settings_page.dart` |

---

## 4. 打包 APK（在你自己的电脑终端，非此沙箱）

Gradle 缓存里只有 9.x，我已把 wrapper 指向 `gradle-9.3.0-bin.zip`（本地已解压），并把 `settings.gradle.kts` 改成 AGP 9.3.0 + Kotlin 2.2.10。若仍报联网下载：
```powershell
cd "E:\ai-develop\AIcoding\Travel diary\android"
& "$env:USERPROFILE\.gradle\wrapper\dists\gradle-9.3.0-bin\bhaiewupfitimu8dp3dbwulm2\gradle-9.3.0\bin\gradle.bat" :app:assembleDebug --offline
```
产物：`build\app\outputs\flutter-apk\app-debug.apk`。更省事的方式是用 Android Studio 打开 `android/` 目录直接 Build APK。
