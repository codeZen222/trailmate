import '../models/expense_model.dart';

/// 解析出的记账意图。
class ExpenseIntent {
  const ExpenseIntent({
    required this.category,
    required this.amountCents,
    required this.note,
    required this.raw,
  });

  final ExpenseCategory category;
  final int amountCents;
  final String note;
  final String raw;

  String get amountText => Money.format(amountCents);
}

/// 极简中文记账语句解析器：从「午餐45」「打车 32块」这类短句里
/// 抽出金额与分类。识别不出金额就返回 null，交给普通聊天处理。
///
/// 设计原则：**宁可少认，不可认错**——只有找到明确金额才生成账单，
/// 且入账前一定会让用户在确认卡上看过分类与备注。
class ExpenseIntentParser {
  ExpenseIntentParser._();

  /// 分类关键词。顺序即优先级：越靠前越优先命中，
  /// 因此把语义更具体的词放前面（如「高铁」优先于泛化的「票」）。
  static const Map<ExpenseCategory, List<String>> _keywords = {
    ExpenseCategory.transport: [
      '高铁', '火车票', '机票', '飞机', '打车', '出租车', '滴滴', '网约车',
      '地铁', '公交', '大巴', '汽车票', '船票', '加油', '停车', '过路费',
      '租车', '索道', '缆车', '摆渡', '车票',
    ],
    ExpenseCategory.stay: [
      '住宿', '酒店', '民宿', '客栈', '青旅', '房租', '开房', '住店', '住',
    ],
    ExpenseCategory.ticket: [
      '门票', '景区', '景点', '展览', '演出', '电影', '入场', '船票观光', '票',
    ],
    ExpenseCategory.food: [
      '午餐', '晚餐', '早餐', '午饭', '晚饭', '早饭', '小吃', '夜宵', '火锅',
      '烧烤', '咖啡', '奶茶', '饮料', '零食', '水果', '餐厅', '饭', '吃', '喝', '面',
    ],
    ExpenseCategory.shopping: [
      '买', '购物', '特产', '纪念品', '衣服', '化妆品', '伴手礼', '超市',
    ],
    ExpenseCategory.fun: [
      '玩', '娱乐', 'KTV', '酒吧', '按摩', '足疗', '漂流', '划船', '潜水',
      '滑翔', '滑雪', '密室', '剧本杀',
    ],
    ExpenseCategory.medical: ['药', '医院', '诊所', '看病', '挂号', '体检'],
  };

  static final RegExp _amountRe = RegExp(
      r'(\d+(?:\.\d{1,2})?)\s*(?:元|块|円|yuan|rmb|￥|¥)?',
      caseSensitive: false);

  /// 返回 null 表示这不是一个记账意图。
  static ExpenseIntent? tryParse(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;

    final matches = _amountRe.allMatches(text).toList();
    if (matches.isEmpty) return null;

    // 取最后一个数字作为金额：「门票120元 龙门石窟」→ 120，
    // 而「2个人 高铁320」→ 320（人数不会被当成金额）
    var picked = matches.last;
    for (final m in matches) {
      // 优先选带货币单位的那个
      final tail = text.substring(m.end).trimLeft();
      if (tail.startsWith('元') ||
          tail.startsWith('块') ||
          text.substring(m.start - 1 < 0 ? 0 : m.start - 1, m.start) == '¥') {
        picked = m;
        break;
      }
    }

    final yuan = double.tryParse(picked.group(1) ?? '');
    if (yuan == null || yuan <= 0 || yuan > 1000000) return null;
    final cents = Money.cents(yuan);

    final category = _matchCategory(text);
    final note = _buildNote(text, picked, category);

    return ExpenseIntent(
      category: category,
      amountCents: cents,
      note: note,
      raw: text,
    );
  }

  static ExpenseCategory _matchCategory(String text) {
    for (final entry in _keywords.entries) {
      for (final k in entry.value) {
        if (text.contains(k)) return entry.key;
      }
    }
    return ExpenseCategory.other;
  }

  /// 去掉金额部分，剩下的当备注；太短则用分类名兜底。
  static String _buildNote(
      String text, RegExpMatch amount, ExpenseCategory category) {
    var note = text
        .replaceFirst(amount.group(0) ?? '', '')
        .replaceAll(RegExp(r'[元块￥¥]'), '')
        .replaceAll(RegExp(r'^[\s，,。、：:；;-]+|[\s，,。、：:；;-]+$'), '')
        .trim();
    if (note.length < 2) note = category.label;
    return note.length > 20 ? note.substring(0, 20) : note;
  }
}
