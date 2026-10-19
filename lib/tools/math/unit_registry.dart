library;

import 'unit_definition.dart';

/// 单位注册表：11 量纲 × 4 transform 模型的**唯一真相源**
/// （`docs/product/calculator.md`「支持量纲与单位对照表」）。
///
/// 别名归一化器集中维护，结果同时服务 `unit_convert`、表达式内联 `to`
/// 与自省 `unit_list`——单一真相源，禁三处各写一份。
class UnitRegistry {
  UnitRegistry._();

  static final List<UnitDefinition> _units = _build();

  /// 归一化别名 → 单位定义（含 id 自身）。
  ///
  /// **冲突即抛**：同一归一化键归属两个不同单位时 fail-fast，禁静默覆盖
  /// （裸 `c` 在 Celsius 与光速间的歧义即靠此拦截，见 [unitsOf] 光速条注释）。
  static final Map<String, UnitDefinition> _byAlias = _buildAliasMap();

  /// 符号归一映射（calculator.md 显式列举的几类）。
  static const Map<String, String> _charMap = {
    '℃': 'celsius',
    '°c': 'celsius',
    '℉': 'fahrenheit',
    '°f': 'fahrenheit',
    'm²': 'm2',
    'm³': 'm3',
    'sq ft': 'ft2',
    'sqft': 'ft2',
  };

  /// 小写 + 去空白 + 符号归一；顺序不可调换（`sq ft` 须在去空白前替换）。
  static String normalizeUnitKey(String raw) {
    var s = raw.trim().toLowerCase();
    for (final e in _charMap.entries) {
      s = s.replaceAll(e.key, e.value);
    }
    return s.replaceAll(RegExp(r'\s+'), '');
  }

  /// 查单位；未命中返回 null（调用方转 `UNKNOWN_UNIT` + candidates）。
  static UnitDefinition? find(String raw) => _byAlias[normalizeUnitKey(raw)];

  /// 全部量纲名（升序，`unit_list` 无参时的一级目录）。
  static final List<String> dimensions =
      _units.map((u) => u.dimension).toSet().toList()..sort();

  /// 某量纲下的全部单位。
  static List<UnitDefinition> unitsOf(String dimension) =>
      _units.where((u) => u.dimension == dimension).toList(growable: false);

  /// 量纲的基准单位（calculator.md「支持量纲与单位对照表」基准列，显式登记）。
  ///
  /// 基准单位 id **不等于** dimension 名（如 `area` 的基准是 `m2`、
  /// `storage` 的基准是 `b`），故用显式表而非约定推导。
  static const Map<String, String> _baseUnitIds = {
    'length': 'm',
    'mass': 'kg',
    'time': 's',
    'temperature': 'K',
    'area': 'm2',
    'volume': 'l',
    'speed': 'm/s',
    'storage': 'b',
    'pressure': 'pa',
    'power': 'w',
    'fuel_economy': 'l/100km',
  };

  static UnitDefinition? baseOf(String dimension) {
    final baseId = _baseUnitIds[dimension];
    if (baseId == null) return null;
    return _units.firstWhere(
      (u) => u.dimension == dimension && u.id == baseId,
      orElse: () => throw StateError(
          '量纲 $dimension 登记的基准单位 $baseId 不在注册表中'),
    );
  }

  /// 全部单位（`unit_list` 不带 dimension 时的展开面）。
  static List<UnitDefinition> get allUnits => List.unmodifiable(_units);

  /// 近邻候选（`UNKNOWN_UNIT` 自愈用）：id/别名的包含与前缀匹配，最多 [limit] 个。
  ///
  /// 两条防噪规则（实测踩坑）：① **单字符 id 不参与子串匹配**——否则 `mphs`
  /// 会把 `m`/`s`/`h` 全判为高分子串，候选退化为无信息量的单字母；
  /// ② 同分按 **id 长度降序**——长 id 更像真实意图。
  static List<String> findSimilar(String raw, {int limit = 3}) {
    final key = normalizeUnitKey(raw);
    if (key.isEmpty) return const <String>[];
    final scored = <MapEntry<String, int>>[];
    for (final u in _units) {
      final id = u.id.toLowerCase();
      if (id == key) continue;
      var score = 0;
      if (id.length >= 2 &&
          key.length >= 2 &&
          (id.contains(key) || key.contains(id))) {
        score = 2;
      } else if (id.startsWith(key) || key.startsWith(id)) {
        score = 1;
      } else if (u.aliases.any((a) {
        final na = normalizeUnitKey(a);
        return na.length >= 2 && (na.contains(key) || key.contains(na));
      })) {
        score = 1;
      }
      if (score > 0) scored.add(MapEntry(u.id, score));
    }
    scored.sort((a, b) {
      final byScore = b.value.compareTo(a.value);
      if (byScore != 0) return byScore;
      return b.key.length.compareTo(a.key.length);
    });
    return scored.take(limit).map((e) => e.key).toList(growable: false);
  }

  static Map<String, UnitDefinition> _buildAliasMap() {
    final m = <String, UnitDefinition>{};
    for (final u in _units) {
      final keys = [normalizeUnitKey(u.id), ...u.aliases.map(normalizeUnitKey)];
      for (final k in keys) {
        final existing = m[k];
        // 冲突 fail-fast：别名歧义必须在入库时暴露，禁静默覆盖（后写赢）。
        if (existing != null && existing.id != u.id) {
          throw StateError('单位别名冲突: "$k" 同时归属 '
              '${existing.id}(${existing.dimension}) 与 ${u.id}(${u.dimension})');
        }
        m[k] = u;
      }
    }
    return m;
  }

  static List<UnitDefinition> _build() => const [
        // ── length（基准 m）──────────────────────────────────────────
        UnitDefinition(id: 'm', name: '米', dimension: 'length',
            aliases: ['meter', 'metre', '米'], symbols: ['m', '米']),
        UnitDefinition(id: 'km', name: '千米', dimension: 'length', factor: 1000,
            aliases: ['kilometer', 'kilometre', '千米', '公里'],
            symbols: ['km', '千米', '公里']),
        UnitDefinition(id: 'cm', name: '厘米', dimension: 'length', factor: 0.01,
            aliases: ['centimeter', '厘米'], symbols: ['cm', '厘米']),
        UnitDefinition(id: 'mm', name: '毫米', dimension: 'length', factor: 0.001,
            aliases: ['millimeter', '毫米'], symbols: ['mm', '毫米']),
        UnitDefinition(id: 'in', name: '英寸', dimension: 'length', factor: 0.0254,
            aliases: ['inch', 'inches', '英寸'], symbols: ['in', '英寸']),
        UnitDefinition(id: 'ft', name: '英尺', dimension: 'length', factor: 0.3048,
            aliases: ['foot', 'feet', '英尺'], symbols: ['ft', '英尺']),
        UnitDefinition(id: 'yd', name: '码', dimension: 'length', factor: 0.9144,
            aliases: ['yard', '码'], symbols: ['yd', '码']),
        UnitDefinition(id: 'mi', name: '英里', dimension: 'length', factor: 1609.344,
            aliases: ['mile', 'miles', '英里'], symbols: ['mi', '英里']),
        UnitDefinition(id: 'nmi', name: '海里', dimension: 'length', factor: 1852,
            aliases: ['nauticalmile', '海里'], symbols: ['nmi', '海里']),

        // ── mass（基准 kg）───────────────────────────────────────────
        UnitDefinition(id: 'kg', name: '千克', dimension: 'mass',
            aliases: ['kilogram', '千克', '公斤'], symbols: ['kg', '千克']),
        UnitDefinition(id: 'g', name: '克', dimension: 'mass', factor: 0.001,
            aliases: ['gram', 'gramme', '克'], symbols: ['g', '克']),
        UnitDefinition(id: 'mg', name: '毫克', dimension: 'mass', factor: 1e-6,
            aliases: ['milligram', '毫克'], symbols: ['mg', '毫克']),
        UnitDefinition(id: 't', name: '吨', dimension: 'mass', factor: 1000,
            aliases: ['ton', 'tonne', '吨'], symbols: ['t', '吨']),
        UnitDefinition(id: 'lb', name: '磅', dimension: 'mass', factor: 0.45359237,
            aliases: ['pound', 'pounds', '磅'], symbols: ['lb', '磅']),
        UnitDefinition(id: 'oz', name: '盎司', dimension: 'mass',
            factor: 0.028349523125, aliases: ['ounce', '盎司'],
            symbols: ['oz', '盎司']),
        UnitDefinition(id: '斤', name: '市斤', dimension: 'mass', factor: 0.5,
            aliases: ['jin', '市斤'], symbols: ['斤', '市斤']),
        UnitDefinition(id: '两', name: '市两', dimension: 'mass', factor: 0.05,
            aliases: ['liang'], symbols: ['两']),

        // ── time（基准 s）────────────────────────────────────────────
        UnitDefinition(id: 's', name: '秒', dimension: 'time',
            aliases: ['sec', 'second', '秒'], symbols: ['s', '秒']),
        UnitDefinition(id: 'ms', name: '毫秒', dimension: 'time', factor: 0.001,
            aliases: ['millisecond', '毫秒'], symbols: ['ms', '毫秒']),
        UnitDefinition(id: 'min', name: '分钟', dimension: 'time', factor: 60,
            aliases: ['minute', '分'], symbols: ['min', '分']),
        UnitDefinition(id: 'h', name: '小时', dimension: 'time', factor: 3600,
            aliases: ['hour', 'hr', '小时', '时'], symbols: ['h', '小时']),
        UnitDefinition(id: 'd', name: '天', dimension: 'time', factor: 86400,
            aliases: ['day', '天', '日'], symbols: ['d', '天']),
        UnitDefinition(id: 'wk', name: '周', dimension: 'time', factor: 604800,
            aliases: ['week', '周', '星期'], symbols: ['wk', '周']),
        UnitDefinition(id: 'yr', name: '年', dimension: 'time', factor: 31536000,
            aliases: ['year', '年'], symbols: ['yr', '年']),

        // ── temperature（基准 K，仿射）──────────────────────────────
        UnitDefinition(id: 'K', name: '开尔文', dimension: 'temperature',
            transform: TransformType.affine, factor: 1, offset: 0,
            aliases: ['kelvin', 'k', '开尔文'], symbols: ['K', '开尔文']),
        UnitDefinition(id: 'c', name: '摄氏度', dimension: 'temperature',
            transform: TransformType.affine, factor: 1, offset: 273.15,
            aliases: ['celsius', 'centigrade', '摄氏度'],
            symbols: ['°C', '摄氏度']),
        UnitDefinition(id: 'f', name: '华氏度', dimension: 'temperature',
            transform: TransformType.affine,
            factor: 5 / 9,
            offset: 273.15 - 32 * 5 / 9,
            aliases: ['fahrenheit', '华氏度'], symbols: ['°F', '华氏度']),

        // ── area（基准 m2）──────────────────────────────────────────
        UnitDefinition(id: 'm2', name: '平方米', dimension: 'area',
            aliases: ['squaremeter', '平方米'], symbols: ['m²', '平方米']),
        UnitDefinition(id: 'km2', name: '平方千米', dimension: 'area',
            factor: 1e6, aliases: ['squarekilometer', '平方千米'],
            symbols: ['km²', '平方千米']),
        UnitDefinition(id: 'cm2', name: '平方厘米', dimension: 'area',
            factor: 1e-4, aliases: ['squarecentimeter', '平方厘米'],
            symbols: ['cm²', '平方厘米']),
        UnitDefinition(id: 'ft2', name: '平方英尺', dimension: 'area',
            factor: 0.09290304, aliases: ['squarefoot', '平方英尺'],
            symbols: ['ft²', '平方英尺']),
        UnitDefinition(id: 'ha', name: '公顷', dimension: 'area', factor: 10000,
            aliases: ['hectare', '公顷'], symbols: ['ha', '公顷']),
        UnitDefinition(id: 'acre', name: '英亩', dimension: 'area',
            factor: 4046.8564224, aliases: ['英亩'], symbols: ['acre', '英亩']),
        UnitDefinition(id: '亩', name: '亩', dimension: 'area',
            factor: 2000 / 3, aliases: ['mu'], symbols: ['亩']),

        // ── volume（基准 l）─────────────────────────────────────────
        UnitDefinition(id: 'l', name: '升', dimension: 'volume',
            aliases: ['liter', 'litre', '升'], symbols: ['L', '升']),
        UnitDefinition(id: 'ml', name: '毫升', dimension: 'volume', factor: 0.001,
            aliases: ['milliliter', '毫升'], symbols: ['mL', '毫升']),
        UnitDefinition(id: 'm3', name: '立方米', dimension: 'volume', factor: 1000,
            aliases: ['cubicmeter', '立方米'], symbols: ['m³', '立方米']),
        UnitDefinition(id: 'gal', name: '美制加仑', dimension: 'volume',
            factor: 3.785411784, aliases: ['galus', 'gallon', '加仑'],
            symbols: ['gal', '加仑']),
        UnitDefinition(id: 'gal_uk', name: '英制加仑', dimension: 'volume',
            factor: 4.54609, aliases: ['galuk', 'imperialgallon', '英加仑'],
            symbols: ['gal(UK)', '英加仑']),
        UnitDefinition(id: 'fl_oz', name: '美制液量盎司', dimension: 'volume',
            factor: 0.0295735295625, aliases: ['fluidounce', '液量盎司'],
            symbols: ['fl oz', '液量盎司']),

        // ── speed（基准 m/s）────────────────────────────────────────
        UnitDefinition(id: 'm/s', name: '米每秒', dimension: 'speed',
            aliases: ['mps', 'meterspersecond', '米每秒'],
            symbols: ['m/s', '米每秒']),
        UnitDefinition(id: 'km/h', name: '千米每小时', dimension: 'speed',
            factor: 1 / 3.6, aliases: ['kph', 'kmh', 'kilometersperhour', '千米每小时', '公里每小时'],
            symbols: ['km/h', '千米每小时']),
        UnitDefinition(id: 'mph', name: '英里每小时', dimension: 'speed',
            factor: 0.44704, aliases: ['milesperhour', '英里每小时'],
            symbols: ['mph', '英里每小时']),
        UnitDefinition(id: 'knot', name: '节', dimension: 'speed',
            factor: 0.514444444444444, aliases: ['kn', 'kt', '节'],
            symbols: ['knot', '节']),
        // 注：裸 `c` 归属 temperature 的摄氏度（calculator.md 两处均写 `c`，
        // 构成真实歧义）。光速以 `lightspeed` 为 id、`c` 仅作展示符号、**不入别名表**。
        UnitDefinition(id: 'lightspeed', name: '光速', dimension: 'speed',
            factor: 299792458, aliases: ['光速'], symbols: ['c', '光速']),

        // ── storage（基准 byte，SI / IEC 显式区分）───────────────────
        UnitDefinition(id: 'b', name: '字节', dimension: 'storage',
            transform: TransformType.iecSi, factor: 1,
            aliases: ['byte', 'bytes', '字节'], symbols: ['B', '字节']),
        UnitDefinition(id: 'kb', name: '千字节', dimension: 'storage',
            transform: TransformType.iecSi, factor: 1e3,
            aliases: ['kilobyte', '千字节'], symbols: ['kB', '千字节']),
        UnitDefinition(id: 'mb', name: '兆字节', dimension: 'storage',
            transform: TransformType.iecSi, factor: 1e6,
            aliases: ['megabyte', '兆字节'], symbols: ['MB', '兆字节']),
        UnitDefinition(id: 'gb', name: '吉字节', dimension: 'storage',
            transform: TransformType.iecSi, factor: 1e9,
            aliases: ['gigabyte', '吉字节'], symbols: ['GB', '吉字节']),
        UnitDefinition(id: 'tb', name: '太字节', dimension: 'storage',
            transform: TransformType.iecSi, factor: 1e12,
            aliases: ['terabyte', '太字节'], symbols: ['TB', '太字节']),
        UnitDefinition(id: 'kib', name: '二进制千字节', dimension: 'storage',
            transform: TransformType.iecSi, factor: 1024,
            aliases: ['kibibyte', '二进制千字节'], symbols: ['KiB']),
        UnitDefinition(id: 'mib', name: '二进制兆字节', dimension: 'storage',
            transform: TransformType.iecSi, factor: 1048576,
            aliases: ['mebibyte', '二进制兆字节'], symbols: ['MiB']),
        UnitDefinition(id: 'gib', name: '二进制吉字节', dimension: 'storage',
            transform: TransformType.iecSi, factor: 1073741824,
            aliases: ['gibibyte', '二进制吉字节'], symbols: ['GiB']),
        UnitDefinition(id: 'tib', name: '二进制太字节', dimension: 'storage',
            transform: TransformType.iecSi, factor: 1099511627776,
            aliases: ['tebibyte', '二进制太字节'], symbols: ['TiB']),

        // ── pressure（基准 pa）──────────────────────────────────────
        UnitDefinition(id: 'pa', name: '帕斯卡', dimension: 'pressure',
            aliases: ['pascal', '帕斯卡', '帕'], symbols: ['Pa', '帕斯卡']),
        UnitDefinition(id: 'kpa', name: '千帕', dimension: 'pressure',
            factor: 1000, aliases: ['kilopascal', '千帕'], symbols: ['kPa', '千帕']),
        UnitDefinition(id: 'mpa', name: '兆帕', dimension: 'pressure',
            factor: 1e6, aliases: ['megapascal', '兆帕'], symbols: ['MPa', '兆帕']),
        UnitDefinition(id: 'bar', name: '巴', dimension: 'pressure', factor: 1e5,
            aliases: ['巴'], symbols: ['bar', '巴']),
        UnitDefinition(id: 'psi', name: '磅力每平方英寸', dimension: 'pressure',
            factor: 6894.757293168, aliases: ['磅力每平方英寸'],
            symbols: ['psi']),
        UnitDefinition(id: 'atm', name: '标准大气压', dimension: 'pressure',
            factor: 101325, aliases: ['atmosphere', '标准大气压'],
            symbols: ['atm', '标准大气压']),
        UnitDefinition(id: 'mmhg', name: '毫米汞柱', dimension: 'pressure',
            factor: 133.322387415, aliases: ['毫米汞柱'], symbols: ['mmHg']),

        // ── power（基准 w）──────────────────────────────────────────
        UnitDefinition(id: 'w', name: '瓦', dimension: 'power',
            aliases: ['watt', '瓦'], symbols: ['W', '瓦']),
        UnitDefinition(id: 'kw', name: '千瓦', dimension: 'power', factor: 1000,
            aliases: ['kilowatt', '千瓦'], symbols: ['kW', '千瓦']),
        UnitDefinition(id: 'mw', name: '兆瓦', dimension: 'power', factor: 1e6,
            aliases: ['megawatt', '兆瓦'], symbols: ['MW', '兆瓦']),
        UnitDefinition(id: 'hp', name: '马力', dimension: 'power',
            factor: 735.49875, aliases: ['horsepower', '公制马力', '马力'],
            symbols: ['hp', '马力']),

        // ── fuel_economy（基准 l/100km，反比例）─────────────────────
        UnitDefinition(id: 'l/100km', name: '升每百公里', dimension: 'fuel_economy',
            transform: TransformType.reciprocal, reciprocalK: 1,
            aliases: ['lper100km', '升每百公里'], symbols: ['L/100km']),
        UnitDefinition(id: 'km/l', name: '千米每升', dimension: 'fuel_economy',
            transform: TransformType.reciprocal, reciprocalK: 100,
            aliases: ['kmperl', '千米每升', '公里每升'], symbols: ['km/L']),
        UnitDefinition(id: 'mpg', name: '英里每加仑', dimension: 'fuel_economy',
            transform: TransformType.reciprocal, reciprocalK: 235.215,
            aliases: ['mpgus', 'milespergallon', '英里每加仑'],
            symbols: ['mpg', '英里每加仑']),
        UnitDefinition(id: 'mpg_uk', name: '英里每英加仑', dimension: 'fuel_economy',
            transform: TransformType.reciprocal, reciprocalK: 282.48,
            aliases: ['milespergallonuk', '英里每英加仑'], symbols: ['mpg(UK)']),
      ];
}
