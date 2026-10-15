/// Cardock Signature V7 fixed themes plus the retained user Custom theme.
///
/// The legacy in-app families standard / prime / vivid / mono are intentionally
/// removed from the active enum. AppearancePreferences v1-v3 must migrate their
/// persisted string values before v4 parsing.
enum CardockThemeFamily {
  ceramicBlue,
  sakuraMist,
  paperArchive,
  lilacMoon,
  glacierBlue,
  mistCoral,
  neonZero,
  obsidianGold,
  custom,
}

/// The shared first-launch theme and the sole free in-app palette.
const CardockThemeFamily cardockDefaultThemeFamily =
    CardockThemeFamily.paperArchive;

const List<CardockThemeFamily> cardockFixedThemeFamilies = <CardockThemeFamily>[
  CardockThemeFamily.ceramicBlue,
  CardockThemeFamily.sakuraMist,
  CardockThemeFamily.paperArchive,
  CardockThemeFamily.lilacMoon,
  CardockThemeFamily.glacierBlue,
  CardockThemeFamily.mistCoral,
  CardockThemeFamily.neonZero,
  CardockThemeFamily.obsidianGold,
];

const List<CardockThemeFamily> cardockSelectableThemeFamilies =
    <CardockThemeFamily>[
      ...cardockFixedThemeFamilies,
      CardockThemeFamily.custom,
    ];

extension CardockThemeFamilyLabel on CardockThemeFamily {
  String get label => switch (this) {
    CardockThemeFamily.ceramicBlue => '瓷蓝晴光',
    CardockThemeFamily.sakuraMist => '樱雾柔光',
    CardockThemeFamily.paperArchive => '橙墨旧刊',
    CardockThemeFamily.lilacMoon => '月纱丁香',
    CardockThemeFamily.glacierBlue => '冰川蓝釉',
    CardockThemeFamily.mistCoral => '雾海珊瑚',
    CardockThemeFamily.neonZero => '零域荧绿',
    CardockThemeFamily.obsidianGold => '曜石鎏金',
    CardockThemeFamily.custom => '自定义',
  };

  String get description => switch (this) {
    CardockThemeFamily.ceramicBlue => '瓷白、钴蓝与微量暖黄；双向柔光的新拟物表面',
    CardockThemeFamily.sakuraMist => '樱粉、莓红与丁香紫；轻柔雾光',
    CardockThemeFamily.paperArchive => '奶油纸、橄榄、烧橙与油墨黑；硬边纸刊质感',
    CardockThemeFamily.lilacMoon => '月白、丁香与烟紫；缎面柔光',
    CardockThemeFamily.glacierBlue => '冰蓝、海蓝与青色；分层透明的蓝釉玻璃',
    CardockThemeFamily.mistCoral => '薄荷雾、奶油、灰蓝与珊瑚；克制柔和 3D',
    CardockThemeFamily.neonZero => 'OLED 黑、荧光绿与冷白；线框与局部辉光',
    CardockThemeFamily.obsidianGold => '黑曜、石墨与鎏金；金色仅用于关键焦点',
    CardockThemeFamily.custom => '按模块配置浅色与深色，同时保留安全对比度',
  };

  bool get isPremium => this != cardockDefaultThemeFamily;

  bool get isFixed => this != CardockThemeFamily.custom;

  /// All V7 in-app marks use the runtime Logo C painter. Launcher icons remain
  /// a separate, fixed Android alias domain.
  bool get usesRuntimeBrandMark => true;

  CardockLauncherFamily? get recommendedLauncherFamily => switch (this) {
    CardockThemeFamily.ceramicBlue => CardockLauncherFamily.ceramicBlue,
    CardockThemeFamily.sakuraMist => CardockLauncherFamily.sakuraMist,
    CardockThemeFamily.paperArchive => CardockLauncherFamily.paperArchive,
    CardockThemeFamily.lilacMoon => CardockLauncherFamily.lilacMoon,
    CardockThemeFamily.glacierBlue => CardockLauncherFamily.glacierBlue,
    CardockThemeFamily.mistCoral => CardockLauncherFamily.mistCoral,
    CardockThemeFamily.neonZero => CardockLauncherFamily.neonZero,
    CardockThemeFamily.obsidianGold => CardockLauncherFamily.obsidianGold,
    CardockThemeFamily.custom => null,
  };
}

/// The eight launcher variants backed by Android aliases and packaged assets.
enum CardockLauncherFamily {
  ceramicBlue,
  sakuraMist,
  paperArchive,
  lilacMoon,
  glacierBlue,
  mistCoral,
  neonZero,
  obsidianGold,
}

const Set<CardockLauncherFamily> cardockLauncherFamilies =
    <CardockLauncherFamily>{
      CardockLauncherFamily.ceramicBlue,
      CardockLauncherFamily.sakuraMist,
      CardockLauncherFamily.paperArchive,
      CardockLauncherFamily.lilacMoon,
      CardockLauncherFamily.glacierBlue,
      CardockLauncherFamily.mistCoral,
      CardockLauncherFamily.neonZero,
      CardockLauncherFamily.obsidianGold,
    };

extension CardockLauncherFamilyLabel on CardockLauncherFamily {
  String get label => switch (this) {
    CardockLauncherFamily.ceramicBlue => '瓷蓝晴光',
    CardockLauncherFamily.sakuraMist => '樱雾柔光',
    CardockLauncherFamily.paperArchive => '橙墨旧刊',
    CardockLauncherFamily.lilacMoon => '月纱丁香',
    CardockLauncherFamily.glacierBlue => '冰川蓝釉',
    CardockLauncherFamily.mistCoral => '雾海珊瑚',
    CardockLauncherFamily.neonZero => '零域荧绿',
    CardockLauncherFamily.obsidianGold => '曜石鎏金',
  };

  String get launcherAssetName =>
      'assets/branding/cardock_launcher_$resourceSlug.png';

  String get resourceSlug => switch (this) {
    CardockLauncherFamily.ceramicBlue => 'ceramic_blue',
    CardockLauncherFamily.sakuraMist => 'sakura_mist',
    CardockLauncherFamily.paperArchive => 'paper_archive',
    CardockLauncherFamily.lilacMoon => 'lilac_moon',
    CardockLauncherFamily.glacierBlue => 'glacier_blue',
    CardockLauncherFamily.mistCoral => 'mist_coral',
    CardockLauncherFamily.neonZero => 'neon_zero',
    CardockLauncherFamily.obsidianGold => 'obsidian_gold',
  };
}

CardockThemeFamily? cardockThemeFamilyFromName(Object? value) {
  if (value is! String) return null;
  for (final family in CardockThemeFamily.values) {
    if (family.name == value) return family;
  }
  return null;
}

/// Only for AppearancePreferences v1-v3 migration.
///
/// v1/v2 never contained Mono or Custom. Keeping this historical boundary
/// prevents a forged old payload from gaining semantics that did not exist.
CardockThemeFamily? cardockLegacyThemeFamilyFromName(
  Object? value, {
  required int formatVersion,
}) {
  if (formatVersion == 1 || formatVersion == 2) {
    return switch (value) {
      'standard' => CardockThemeFamily.ceramicBlue,
      'prime' => CardockThemeFamily.obsidianGold,
      'vivid' => CardockThemeFamily.mistCoral,
      _ => null,
    };
  }
  if (formatVersion == 3) {
    return switch (value) {
      'standard' => CardockThemeFamily.ceramicBlue,
      'prime' => CardockThemeFamily.obsidianGold,
      'vivid' => CardockThemeFamily.mistCoral,
      'mono' => CardockThemeFamily.neonZero,
      'custom' => CardockThemeFamily.custom,
      _ => null,
    };
  }
  return null;
}

CardockLauncherFamily? cardockLauncherFamilyFromName(Object? value) {
  if (value is! String) return null;
  for (final family in cardockLauncherFamilies) {
    if (family.name == value) return family;
  }
  return switch (value) {
    'standard' => CardockLauncherFamily.ceramicBlue,
    'prime' => CardockLauncherFamily.obsidianGold,
    'vivid' => CardockLauncherFamily.mistCoral,
    _ => null,
  };
}

bool isLegacyCardockLauncherFamilyName(Object? value) =>
    value == 'standard' || value == 'prime' || value == 'vivid';

CardockLauncherFamily resolveCardockLauncherFamily({
  required CardockThemeFamily themeFamily,
  required CardockLauncherFamily customFallback,
}) => themeFamily.recommendedLauncherFamily ?? customFallback;
