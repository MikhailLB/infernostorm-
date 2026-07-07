import 'gate_config.dart';
import 'forge_keys.dart';
import 'api_routes.dart';

class AppConfig {
  static const String bundleId = 'com.siegeburn.infernstorm';
  static const String storeId  = 'com.siegeburn.infernstorm';
  static const String appName  = 'InfernoStorm';

  // iOS App Store numeric ID — not used on Android
  static const String analyticsAppId = '';

  static String get configEndpoint => resolveConfigEndpoint();
  static String get flowKey        => resolveFlowKey();
  static String get messagingId    => resolveMessagingId();

  static String get privacyPolicy  => privacyPolicyUrl;
  static String get support        => supportUrl;

  // Push skip delay — 3 days in seconds
  static const int notifRetrySeconds = 259200;

  // GCD retry delay when AF returns Organic on first callback
  static const int gcdRetrySeconds = 5;
}
