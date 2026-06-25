import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Mini WebView for legal pages (Privacy Policy / Support) from game menu.
/// Shown in white (game) mode only.
class InfoPanel extends StatefulWidget {
  final String title;
  final String url;

  const InfoPanel({super.key, required this.title, required this.url});

  @override
  State<InfoPanel> createState() => _InfoPanelState();
}

class _InfoPanelState extends State<InfoPanel> {
  late final WebViewController _ctrl;
  bool _loading = true;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    _ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) {
          setState(() {
            _progress = p / 100.0;
            if (p == 100) _loading = false;
          });
        },
        onPageStarted: (_) => setState(() => _loading = true),
        onPageFinished: (_) => setState(() => _loading = false),
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.deepOrange.shade900,
        foregroundColor: Colors.orange.shade100,
        title: Text(widget.title,
            style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.of(context).pop(),
        ),
        bottom: _loading
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: Colors.deepOrange.shade900,
                  valueColor: AlwaysStoppedAnimation(Colors.orange.shade300),
                ),
              )
            : null,
      ),
      body: WebViewWidget(controller: _ctrl),
    );
  }
}
