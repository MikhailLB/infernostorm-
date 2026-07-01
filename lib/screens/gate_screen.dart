import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import '../net/blaze_storage.dart';
import '../net/launch_bridge.dart';
import '../net/net_probe.dart';
import '../net/signal_service.dart';
import 'offline_wall.dart';

/// Pre-warm WebView engine before navigation (deferred import helper).
Future<void> prepareGateEngine() async {}

class GateScreen extends StatefulWidget {
  final String url;
  final BlazeStorage storage;
  final SignalService signal;
  final NetProbe probe;

  const GateScreen({
    super.key,
    required this.url,
    required this.storage,
    required this.signal,
    required this.probe,
  });

  @override
  State<GateScreen> createState() => _GateScreenState();
}

class _GateScreenState extends State<GateScreen> with WidgetsBindingObserver {
  late final WebViewController _ctrl;
  bool _loading = true;
  bool _goingOffline = false;
  Timer? _offlineDebounce;

  String? _lastMainUrl;
  int _redirectRetries = 0;

  void _applyImmersive() =>
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _applyImmersive();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _applyImmersive();

    _ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(httpBridge.userAgent)
      ..setBackgroundColor(Colors.black)
      ..enableZoom(false)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() => _loading = true);
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
          _redirectRetries = 0;
          _injectAreaKill();
          _injectKeyboardFix();
        },
        onWebResourceError: (err) {
          if (err.isForMainFrame != true) return;

          // Cover native error page immediately with spinner
          if (mounted) setState(() => _loading = true);

          final desc = err.description.toLowerCase();
          final isTooMany = desc.contains('too_many_redirects') ||
              err.errorCode == -1007 ||
              err.errorCode == -9;

          if (isTooMany && _lastMainUrl != null && _redirectRetries < 3) {
            _redirectRetries++;
            _ctrl.loadRequest(Uri.parse(_lastMainUrl!));
            return;
          }

          final isDns = desc.contains('name_not_resolved') ||
              desc.contains('internet_disconnected') ||
              desc.contains('network_changed') ||
              err.errorCode == -105 ||
              err.errorCode == -106 ||
              err.errorCode == -21;

          if (isDns) {
            _goOfflineDirect();
          } else {
            _checkOffline();
          }
        },
        onHttpError: (_) {},
        onNavigationRequest: (req) {
          final uri = Uri.tryParse(req.url);
          if (uri == null) return NavigationDecision.prevent;
          final s = uri.scheme;
          if (s == 'http' ||
              s == 'https' ||
              s == 'about' ||
              s == 'data' ||
              s == 'blob') {
            if (req.isMainFrame) _lastMainUrl = req.url;
            return NavigationDecision.navigate;
          }
          _launchExternal(uri);
          return NavigationDecision.prevent;
        },
      ));

    _setupAndroid();
    _ctrl.loadRequest(Uri.parse(widget.url));

    // Warm push URL redirect
    widget.signal.onPushUrl = (url) {
      if (mounted) _ctrl.loadRequest(Uri.parse(url));
    };

    // Connectivity drop — debounced 700ms to handle VPN flicker
    widget.probe.statusStream.listen((results) {
      final allNone = results.every((r) => r == ConnectivityResult.none);
      if (!allNone) {
        _offlineDebounce?.cancel();
        return;
      }
      _offlineDebounce?.cancel();
      _offlineDebounce = Timer(
        const Duration(milliseconds: 700),
        _checkOffline,
      );
    });
  }

  void _setupAndroid() {
    if (Platform.isAndroid && _ctrl.platform is AndroidWebViewController) {
      final a = _ctrl.platform as AndroidWebViewController;
      a.setMediaPlaybackRequiresUserGesture(false);
      a.setOnShowFileSelector(_pickFile);
      final cm = AndroidWebViewCookieManager(
        AndroidWebViewCookieManagerCreationParams
            .fromPlatformWebViewCookieManagerCreationParams(
          const PlatformWebViewCookieManagerCreationParams(),
        ),
      );
      cm.setAcceptThirdPartyCookies(a, true);
    }
  }

  Future<List<String>> _pickFile(FileSelectorParams params) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: params.mode == FileSelectorMode.openMultiple,
        type: FileType.any,
      );
      if (result != null && result.files.isNotEmpty) {
        return result.files
            .where((f) => f.path != null)
            .map((f) => Uri.file(f.path!).toString())
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> _checkOffline() async {
    if (_goingOffline) return;
    final online = await widget.probe.isOnline();
    if (online || !mounted) return;
    _goOfflineDirect();
  }

  void _goOfflineDirect() {
    if (_goingOffline) return;
    _goingOffline = true;
    _offlineDebounce?.cancel();
    _ctrl.currentUrl().then((cur) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => OfflineWall(
            onRetry: (_) => GateScreen(
              url: cur ?? widget.url,
              storage: widget.storage,
              signal: widget.signal,
              probe: widget.probe,
            ),
          ),
        ),
      );
    });
  }

  void _injectAreaKill() {
    _ctrl.runJavaScript(r'''
(function() {
  if (window.__isAreaKillActive) return;
  window.__isAreaKillActive = true;
  var CSS_ID = '__isa';
  var CSS = ':root{--safe-area-inset-top:0px!important;--safe-area-inset-right:0px!important;'
    +'--safe-area-inset-bottom:0px!important;--safe-area-inset-left:0px!important;'
    +'--sat:0px!important;--sar:0px!important;--sab:0px!important;--sal:0px!important;}'
    +'html,body,#__nuxt,#app,#root{padding-top:0!important;margin-top:0!important;}';
  function apply() {
    var head = document.head || document.documentElement;
    if (!head) return;
    var m = document.querySelector('meta[name="viewport"]');
    if (m) {
      var c = (m.getAttribute('content')||'').replace(/,?\\s*viewport-fit\\s*=\\s*\\w+/ig,'').trim();
      m.setAttribute('content', c + (c?', ':'') + 'viewport-fit=contain');
    }
    var s = document.getElementById(CSS_ID);
    if (!s){s=document.createElement('style');s.id=CSS_ID;head.appendChild(s);}
    if (s.textContent!==CSS) s.textContent=CSS;
  }
  apply();
  ['pushState','replaceState'].forEach(function(fn){
    var o=history[fn];history[fn]=function(){var r=o.apply(this,arguments);setTimeout(apply,90);return r;};
  });
  window.addEventListener('popstate',function(){setTimeout(apply,90);});
  setInterval(function(){if(!window.visualViewport||window.visualViewport.height>=window.innerHeight*0.75)apply();},2500);
})();
''');
  }

  void _injectKeyboardFix() {
    _ctrl.runJavaScript('''
(function(){
  if(window.__kbfx) return;
  window.__kbfx=true;
  function isInput(el){return el&&(el.tagName==='INPUT'||el.tagName==='TEXTAREA'||el.isContentEditable);}
  function doScroll(){
    var el=document.activeElement;
    if(!isInput(el)) return;
    var vp=window.visualViewport;
    if(vp){
      var r=el.getBoundingClientRect();
      var vb=vp.offsetTop+vp.height;
      if(r.bottom>vb-20||r.top<vp.offsetTop) el.scrollIntoView({behavior:'auto',block:'nearest'});
    } else el.scrollIntoView({behavior:'auto',block:'nearest'});
  }
  document.addEventListener('focusin',function(e){if(isInput(e.target))setTimeout(doScroll,350);});
  if(window.visualViewport){
    var ph=window.visualViewport.height;
    window.visualViewport.addEventListener('resize',function(){
      var h=window.visualViewport.height;if(h<ph)setTimeout(doScroll,120);ph=h;
    });
  }
})();
''');
  }

  Future<void> _launchExternal(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _offlineDebounce?.cancel();
    widget.signal.onPushUrl = null;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: SystemUiOverlay.values);
    // NOTE: do NOT lock orientation here — next screen's initState wins
    // (e.g. OfflineWall needs all 4 orientations and would be overridden).
    super.dispose();
  }

  Future<bool> _handleBack() async {
    if (await _ctrl.canGoBack()) {
      await _ctrl.goBack();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _handleBack();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset:
            false, // critical — no double-resize with adjustResize
        body: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              // Portrait: keep top safe zone (status bar / notch cutout).
              // Landscape: edge-to-edge (no top, no side padding).
              padding: () {
                final vp = MediaQuery.of(context).viewPadding;
                final isLand =
                    MediaQuery.of(context).orientation == Orientation.landscape;
                return EdgeInsets.only(top: isLand ? 0 : vp.top);
              }(),
              child: WebViewWidget(controller: _ctrl),
            ),
            if (_loading)
              Container(
                color: Colors.black.withValues(alpha: 0.55),
                child: const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation(Colors.deepOrange),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
