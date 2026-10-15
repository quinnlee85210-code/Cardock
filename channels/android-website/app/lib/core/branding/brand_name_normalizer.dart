import 'package:unorm_dart/unorm_dart.dart' as unorm;

const cardockBrandNormalizationPolicy =
    'unicode_nfkc_v1_runtime_unorm_dart_0.3.2_unicode17_build_corpus_parity_v1';

/// Cardock 品牌匹配使用的 Unicode NFKC 归一化。
///
/// 顺序固定为 NFKC、转小写，再移除约定的 Unicode 空白与标点连接符。
/// NFKC 由锁定为 Unicode 17.0 数据的纯 Dart 依赖离线完成。
String normalizeCardockBrandName(String input) {
  final folded = unorm.nfkc(input).toLowerCase();
  final result = StringBuffer();
  for (final rune in folded.runes) {
    if (_ignoredBrandSeparators.contains(rune) || _isWhitespace(rune)) {
      continue;
    }
    result.writeCharCode(rune);
  }
  return result.toString();
}

bool _isWhitespace(int rune) => _brandWhitespace.contains(rune);

// Unicode White_Space 属性的固定集合。生成器使用同一集合，不依赖宿主
// Python 的 str.isspace()，避免构建机 Unicode 数据版本造成索引漂移。
const _brandWhitespace = <int>{
  0x0009,
  0x000A,
  0x000B,
  0x000C,
  0x000D,
  0x0020,
  0x0085,
  0x00A0,
  0x1680,
  0x2000,
  0x2001,
  0x2002,
  0x2003,
  0x2004,
  0x2005,
  0x2006,
  0x2007,
  0x2008,
  0x2009,
  0x200A,
  0x2028,
  0x2029,
  0x202F,
  0x205F,
  0x3000,
};

const _ignoredBrandSeparators = <int>{
  0x0021, // !
  0x0022, // "
  0x0023, // #
  0x0024, // $
  0x0025, // %
  0x0026, // &
  0x0027, // '
  0x0028, // (
  0x0029, // )
  0x002A, // *
  0x002B, // +
  0x002C, // ,
  0x002D, // -
  0x002E, // .
  0x002F, // /
  0x003A, // :
  0x003B, // ;
  0x003C, // <
  0x003D, // =
  0x003E, // >
  0x003F, // ?
  0x0040, // @
  0x005B, // [
  0x005C, // backslash
  0x005D, // ]
  0x005E, // ^
  0x005F, // _
  0x0060, // `
  0x007B, // {
  0x007C, // |
  0x007D, // }
  0x007E, // ~
  0x00B7, // middle dot
  0x2010, // hyphen
  0x2011, // non-breaking hyphen
  0x2012, // figure dash
  0x2013, // en dash
  0x2014, // em dash
  0x2015, // horizontal bar
  0x2022, // bullet
  0x2026, // ellipsis
  0x2212, // minus sign
  0x3001, // ideographic comma
  0x3002, // ideographic full stop
  0xFE58, // small em dash
  0xFE63, // small hyphen-minus
  0xFF0C, // fullwidth comma
  0xFF1A, // fullwidth colon
  0xFF1B, // fullwidth semicolon
};
