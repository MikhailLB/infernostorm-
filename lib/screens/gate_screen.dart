import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import '../bridge/insight.dart';
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

  // Clarity funnel state.
  bool _offerReached = false; // first successful main-frame load happened
  bool _pageHadError = false; // reset each navigation; blocks false success

  // High-cardinality patterns for the offer/auth/cashier funnel.
  static final RegExp _depositRx = RegExp(
    r'(deposit|cashier|top.?up|replenish|payment|checkout|wallet|пополн|депозит|касс|оплат|внести|платеж)',
    caseSensitive: false,
  );
  static final RegExp _registerRx = RegExp(
    r'(sign.?up|regist|create.?account|onboarding|регистрац|зарегистр)',
    caseSensitive: false,
  );
  static final RegExp _loginRx = RegExp(
    r'(sign.?in|log.?in|log.?on|/auth\b|authoriz|войти|вход|авториз)',
    caseSensitive: false,
  );

  void _applyImmersive() =>
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _applyImmersive();
      Insight.event('web_foreground');
    } else if (state == AppLifecycleState.paused) {
      Insight.event('web_background');
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Insight.screen('web');
    Insight.event('web_open');

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
      ..addJavaScriptChannel(
        'AegisInsight',
        onMessageReceived: (msg) => _onWebSignal(msg.message),
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          _pageHadError = false;
          if (mounted) setState(() => _loading = true);
        },
        onPageFinished: (url) {
          if (mounted) setState(() => _loading = false);
          _redirectRetries = 0;
          _injectAreaKill();
          _injectKeyboardFix();
          _installInsightProbe();
          _trackWebPage(url);
        },
        onWebResourceError: (err) {
          if (err.isForMainFrame != true) return;
          _pageHadError = true;
          _reportWebError(err);

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
          // External deep-link hand-off (payment intent, tg://, mailto:, etc.)
          Insight.event('web_external');
          Insight.tag('web_external_scheme', uri.scheme);
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

  // ── Clarity funnel tracking ─────────────────────────────────────────────

  /// Called on every successful main-frame page finish. Sets the
  /// per-URL screen label, emits `web_page`, flips `_offerReached` on
  /// the first clean load, and tags cashier/auth reachability.
  void _trackWebPage(String url) {
    final Uri? uri = Uri.tryParse(url);
    final String label = uri == null ? url : '${uri.host}${uri.path}';
    Insight.screenName('web:$label');
    Insight.event('web_page');
    Insight.tag('web_last_url', url);
    if (!_offerReached && !_pageHadError) {
      _offerReached = true;
      Insight.event('web_offer_reached');
      Insight.tag('offer_reached', 'true');
      if (uri?.host != null) Insight.tag('offer_host', uri!.host);
    }
    if (_depositRx.hasMatch(url)) {
      Insight.event('web_cashier_page');
      Insight.tag('reached_cashier', 'true');
    }
    _trackAuthPage(url);
  }

  void _trackAuthPage(String url) {
    if (_registerRx.hasMatch(url)) {
      Insight.event('web_register_page');
      Insight.tag('reached_register', 'true');
    } else if (_loginRx.hasMatch(url)) {
      Insight.event('web_login_page');
      Insight.tag('reached_login', 'true');
    }
  }

  void _reportWebError(WebResourceError err) {
    final String reason = _classifyWebError(err);
    final String failed = _lastMainUrl ?? widget.url;
    final String host = Uri.tryParse(failed)?.host ?? '';
    Insight.event('web_error');
    Insight.tag('web_error_reason', reason);
    Insight.tag('web_last_error', '${err.errorCode}:${err.description}');
    if (host.isNotEmpty) Insight.tag('web_error_host', host);
    if (!_offerReached) {
      Insight.event('web_offer_unreachable');
      Insight.tag('offer_reached', 'false');
      Insight.tag('offer_unreachable_reason', reason);
    } else {
      Insight.event('web_error_after_load');
    }
  }

  static String _classifyWebError(WebResourceError err) {
    final String d = err.description.toLowerCase();
    final int c = err.errorCode;
    if (d.contains('connection_refused') ||
        d.contains('connection refused')) {
      return 'connection_refused';
    }
    if (d.contains('too_many_redirects') ||
        d.contains('too many redirects')) {
      return 'redirect_loop';
    }
    if (d.contains('name_not_resolved') ||
        d.contains('address_unreachable') ||
        d.contains('unknownhost') ||
        c == -2) {
      return 'dns_unresolved';
    }
    if (d.contains('timed out') || d.contains('timeout') || c == -8) {
      return 'timeout';
    }
    if (d.contains('internet_disconnected') ||
        d.contains('network_changed') ||
        c == -6) {
      return 'no_network';
    }
    if (d.contains('connection_reset')) return 'connection_reset';
    if (d.contains('connection_closed') ||
        d.contains('empty_response')) {
      return 'connection_closed';
    }
    if (d.contains('ssl') || d.contains('cert') || c == -11) return 'ssl_error';
    if (d.contains('blocked')) return 'blocked';
    return 'other';
  }

  /// Injects an idempotent JS probe that reports SPA route changes,
  /// deposit/register/login clicks, and auth form submits over the
  /// `AegisInsight` channel. Safe to re-run on every page finish.
  void _installInsightProbe() {
    _ctrl.runJavaScript(r'''
(function(){
  if (window.__aegisInsight) return; window.__aegisInsight = true;
  function send(t){ try { AegisInsight.postMessage(t); } catch(e){} }
  var DEP=/(deposit|cashier|top.?up|add funds|replenish|payment|pay now|checkout|withdraw|пополн|депозит|касс|оплат|внести|вывод|платеж)/i;
  var REG=/(sign.?up|regist|create.?account|регистрац|зарегистр)/i;
  var LOG=/(sign.?in|log.?in|log.?on|войти|вход|авториз)/i;
  var lastPath='';
  function reportPath(){ var p=location.pathname+location.search; if(p!==lastPath){ lastPath=p; send('path:'+p);} }
  reportPath();
  ['pushState','replaceState'].forEach(function(fn){ var o=history[fn]; history[fn]=function(){ var r=o.apply(this,arguments); setTimeout(reportPath,60); return r; }; });
  window.addEventListener('popstate',function(){ setTimeout(reportPath,60); });
  document.addEventListener('click',function(e){
    try{ var el=e.target;
      for(var i=0;i<4&&el;i++){
        var t=((el.innerText||el.value||(el.getAttribute&&el.getAttribute('aria-label'))||'')+'').trim();
        if(t){ if(DEP.test(t)){send('deposit_click:'+t.slice(0,60));return;}
               if(REG.test(t)){send('register_click:'+t.slice(0,60));return;}
               if(LOG.test(t)){send('login_click:'+t.slice(0,60));return;} }
        el=el.parentElement;
      }
    }catch(x){}
  },true);
  document.addEventListener('submit',function(e){
    try{ var f=e.target;
      var pw=f.querySelectorAll?f.querySelectorAll('input[type="password"]'):[];
      var blob=((f.innerText||'')+' '+(f.getAttribute('action')||'')+' '+(f.className||''));
      var confirm=f.querySelector&&(f.querySelector('input[name*="confirm" i]')||f.querySelector('input[name*="repeat" i]'));
      if(pw&&pw.length>=2){send('auth_submit:register');return;}
      if(pw&&pw.length===1){ send('auth_submit:'+((confirm||REG.test(blob))?'register':'login')); return; }
      if(REG.test(blob)){send('auth_submit:register');return;}
      if(LOG.test(blob)){send('auth_submit:login');return;}
      send('form_submit');
    }catch(x){ send('form_submit'); }
  },true);
})();
''');
  }

  void _onWebSignal(String raw) {
    final int i = raw.indexOf(':');
    final String type = i < 0 ? raw : raw.substring(0, i);
    final String data = i < 0 ? '' : raw.substring(i + 1);
    switch (type) {
      case 'path':
        Insight.event('web_spa_route');
        Insight.tag('web_last_path', data);
        if (_depositRx.hasMatch(data)) {
          Insight.event('web_cashier_page');
          Insight.tag('reached_cashier', 'true');
        }
        _trackAuthPage(data);
        break;
      case 'deposit_click':
        Insight.event('web_deposit_click');
        Insight.tag('deposit_intent', 'true');
        if (data.isNotEmpty) Insight.tag('deposit_label', data);
        break;
      case 'register_click':
        Insight.event('web_register_click');
        Insight.tag('register_intent', 'true');
        break;
      case 'login_click':
        Insight.event('web_login_click');
        Insight.tag('login_intent', 'true');
        break;
      case 'auth_submit':
        if (data == 'register') {
          Insight.event('web_register_submit');
          Insight.tag('attempted_register', 'true');
        } else {
          Insight.event('web_login_submit');
          Insight.tag('attempted_login', 'true');
        }
        break;
      case 'form_submit':
        Insight.event('web_form_submit');
        break;
    }
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
              // Portrait: top safe zone (status bar / notch).
              // Landscape: side safe zones (notch on left or right side).
              padding: () {
                final vp = MediaQuery.of(context).viewPadding;
                final isLand =
                    MediaQuery.of(context).orientation == Orientation.landscape;
                return EdgeInsets.only(
                  top: isLand ? 0 : vp.top,
                  left: isLand ? vp.left : 0,
                  right: isLand ? vp.right : 0,
                );
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
