import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'pkce.dart';

class AuthService {
  // ── Configure these for your app ──────────────────────────────────────────
  static const _clientId       = 'client_YOUR_CLIENT_ID';

  // Option A — GitHub Pages (recommended, permanent, no server needed)
  // Set up as described in the README, then use these URIs:
  static const _redirectUri    = 'https://YOUR_GITHUB_USERNAME.github.io/YOUR_REPO_NAME/callback/';
  static const _postLogoutUri  = 'https://YOUR_GITHUB_USERNAME.github.io/YOUR_REPO_NAME/logout/';
  static const _callbackScheme = 'https'; // use 'https' for App Links

  // Option B — Your own domain (production)
  // static const _redirectUri    = 'https://yourdomain.com/callback/';
  // static const _postLogoutUri  = 'https://yourdomain.com/logout/';
  // static const _callbackScheme = 'https';

  // Option C — ngrok (local testing only, URL changes every session)
  // static const _redirectUri    = 'https://xxxx-xxxx.ngrok-free.app/callback/';
  // static const _postLogoutUri  = 'https://xxxx-xxxx.ngrok-free.app/logout/';
  // static const _callbackScheme = 'sudapassdemo';
  // ──────────────────────────────────────────────────────────────────────────

  static const _authorizeUrl  = 'https://sudapass.online/oauth/authorize';
  static const _tokenUrl      = 'https://sudapass.online/oauth/token';
  static const _endSessionUrl = 'https://sudapass.online/oauth/session/end';
  static const _scope         = 'openid profile email national_id';

  final _storage = const FlutterSecureStorage();

  /// Initiates the SudaPass login flow.
  /// Returns true on successful authentication, throws on failure.
  Future<bool> login() async {
    final verifier  = Pkce.generateVerifier();
    final challenge = Pkce.generateChallenge(verifier);
    final state     = Pkce.randomString(16);
    final nonce     = Pkce.randomString(16);

    final authUri = Uri.parse(_authorizeUrl).replace(queryParameters: {
      'response_type':         'code',
      'client_id':             _clientId,
      'redirect_uri':          _redirectUri,
      'scope':                 _scope,
      'state':                 state,
      'nonce':                 nonce,
      'code_challenge':        challenge,
      'code_challenge_method': 'S256',
    });

    final completer = Completer<String>();

    final browser = _SudaPassBrowser(
      onExitCallback: () {
        if (!completer.isCompleted) {
          completer.completeError(Exception('User canceled login'));
        }
      },
      onUrlCallback: (uri) async {
        if (uri.startsWith('$_callbackScheme://')) {
          if (!completer.isCompleted) completer.complete(uri);
          return true;
        }
        return false;
      },
    );

    await browser.openUrlRequest(
      urlRequest: URLRequest(url: WebUri(authUri.toString())),
      settings: InAppBrowserClassSettings(
        webViewSettings: InAppWebViewSettings(
          useShouldOverrideUrlLoading: true,
          javaScriptEnabled: true,
        ),
      ),
    );

    final result = await completer.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () => throw Exception('Login timed out'),
    );

    final callbackUri   = Uri.parse(result);
    final returnedState = callbackUri.queryParameters['state'];
    final code          = callbackUri.queryParameters['code'];

    if (returnedState != state) throw Exception('State mismatch — possible CSRF');
    if (code == null) throw Exception('No authorization code returned');

    final tokenResponse = await http.post(
      Uri.parse(_tokenUrl),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type':    'authorization_code',
        'code':          code,
        'redirect_uri':  _redirectUri,
        'client_id':     _clientId,
        'code_verifier': verifier,
      },
    );

    if (tokenResponse.statusCode != 200) {
      throw Exception('Token exchange failed: ${tokenResponse.body}');
    }

    final tokens = jsonDecode(tokenResponse.body) as Map<String, dynamic>;
    await _storage.write(key: 'access_token',  value: tokens['access_token']);
    await _storage.write(key: 'id_token',      value: tokens['id_token']);
    await _storage.write(key: 'refresh_token', value: tokens['refresh_token']);

    return true;
  }

  /// Logs the user out and clears stored tokens.
  Future<void> logout() async {
    final idToken = await _storage.read(key: 'id_token');
    await _storage.deleteAll();

    final logoutUri = Uri.parse(_endSessionUrl).replace(queryParameters: {
      'id_token_hint':            idToken ?? '',
      'post_logout_redirect_uri': _postLogoutUri,
      'client_id':                _clientId,
    });

    final browser = _SudaPassBrowser(
      onExitCallback: () {},
      onUrlCallback: (uri) async => uri.startsWith('$_callbackScheme://logout'),
    );

    await browser.openUrlRequest(
      urlRequest: URLRequest(url: WebUri(logoutUri.toString())),
      settings: InAppBrowserClassSettings(
        webViewSettings: InAppWebViewSettings(
          useShouldOverrideUrlLoading: true,
          javaScriptEnabled: true,
        ),
      ),
    );
  }

  /// Returns true if an access token is stored.
  Future<bool> isLoggedIn() async {
    return await _storage.read(key: 'access_token') != null;
  }
}

class _SudaPassBrowser extends InAppBrowser {
  final void Function() onExitCallback;
  final Future<bool> Function(String uri) onUrlCallback;

  _SudaPassBrowser({required this.onExitCallback, required this.onUrlCallback});

  @override
  void onExit() => onExitCallback();

  @override
  Future<NavigationActionPolicy?> shouldOverrideUrlLoading(
      NavigationAction action) async {
    final uri = action.request.url?.toString() ?? '';
    final shouldClose = await onUrlCallback(uri);
    if (shouldClose) {
      await close();
      return NavigationActionPolicy.CANCEL;
    }
    return NavigationActionPolicy.ALLOW;
  }
}
