import 'package:flutter/material.dart';
import 'net/blaze_storage.dart';
import 'net/cloud_gateway.dart';
import 'net/flow_controller.dart';
import 'net/net_probe.dart';
import 'net/signal_service.dart';
import 'screens/boot_screen.dart';

class InfernoStormApp extends StatelessWidget {
  final BlazeStorage storage;
  final NetProbe probe;
  final FlowController flow;
  final CloudGateway gateway;
  final SignalService signal;

  const InfernoStormApp({
    super.key,
    required this.storage,
    required this.probe,
    required this.flow,
    required this.gateway,
    required this.signal,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Inferno Storm',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepOrange,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: BootScreen(
        storage: storage,
        probe:   probe,
        flow:    flow,
        gateway: gateway,
        signal:  signal,
      ),
    );
  }
}
