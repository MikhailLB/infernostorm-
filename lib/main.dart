import 'package:clarity_flutter/clarity_flutter.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app.dart';
import 'net/blaze_storage.dart';
import 'net/cloud_gateway.dart';
import 'net/flow_controller.dart';
import 'net/launch_bridge.dart';
import 'net/net_probe.dart';
import 'net/signal_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase — fails silently if google-services.json not yet added
  try {
    await Firebase.initializeApp();
    await FirebaseAppCheck.instance.activate(
      androidProvider: kDebugMode
          ? AndroidProvider.debug
          : AndroidProvider.playIntegrity,
    );
  } catch (_) {}

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  await httpBridge.init();

  final storage = BlazeStorage();
  await storage.init();

  final probe   = NetProbe();
  final flow    = FlowController();
  final gateway = CloudGateway(storage);
  final signal  = SignalService(storage);

  // Microsoft Clarity session recording / heatmaps. Verbose logs only
  // in debug builds so release logcat stays clean.
  final clarityConfig = ClarityConfig(
    projectId: 'xmcu44w75j',
    logLevel: kDebugMode ? LogLevel.Verbose : LogLevel.None,
  );

  runApp(ClarityWidget(
    clarityConfig: clarityConfig,
    app: InfernoStormApp(
      storage: storage,
      probe:   probe,
      flow:    flow,
      gateway: gateway,
      signal:  signal,
    ),
  ));
}
