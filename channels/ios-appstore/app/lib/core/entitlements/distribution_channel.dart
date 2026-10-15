import 'package:flutter/foundation.dart';

enum CardockDistributionChannel {
  development,
  website,
  googlePlay,
  appStore,
  unsupported,
}

extension CardockDistributionChannelValue on CardockDistributionChannel {
  String get wireValue => switch (this) {
    CardockDistributionChannel.development => 'development',
    CardockDistributionChannel.website => 'website',
    CardockDistributionChannel.googlePlay => 'google_play',
    CardockDistributionChannel.appStore => 'app_store',
    CardockDistributionChannel.unsupported => 'unsupported',
  };
  bool get isStore =>
      this == CardockDistributionChannel.googlePlay ||
      this == CardockDistributionChannel.appStore;
}

abstract interface class DistributionAwarePurchaseGateway {
  CardockDistributionChannel get distributionChannel;
}

abstract final class CardockDistributionConfig {
  static const String value = String.fromEnvironment(
    'CARDOCK_DISTRIBUTION',
    defaultValue: 'development',
  );
  static CardockDistributionChannel get channel =>
      resolve(value, platform: defaultTargetPlatform);

  /// iOS must never enter an Android or mock purchase path through missing defines.
  static CardockDistributionChannel resolve(
    String value, {
    required TargetPlatform platform,
  }) {
    if (platform == TargetPlatform.iOS) {
      return value == 'development' || value == 'app_store'
          ? CardockDistributionChannel.appStore
          : CardockDistributionChannel.unsupported;
    }
    return parse(value);
  }

  static CardockDistributionChannel parse(String value) => switch (value) {
    'development' => CardockDistributionChannel.development,
    'website' => CardockDistributionChannel.website,
    'google_play' => CardockDistributionChannel.googlePlay,
    'app_store' => CardockDistributionChannel.appStore,
    _ => CardockDistributionChannel.unsupported,
  };
}
