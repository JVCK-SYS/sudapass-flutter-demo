# SudaPass Flutter Integration Guide

Add **"Sign in with SudaPass"** to your Flutter Android app — national identity authentication, no passwords.

---

## How It Works

```
Your App → SudaPass (citizen authenticates) → Your App receives confirmed login
```

1. Your app opens a browser to the SudaPass login page
2. The citizen enters their national number and authenticates with biometrics via the SudaPass mobile app
3. SudaPass redirects to your redirect URI with an authorization code
4. Your app exchanges the code for tokens — login is complete

---

## Before You Start

Contact NCTR to register your app as a Service Provider. You will receive:

- A **Client ID** (`client_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`)
- Confirmation that your **redirect URI** is registered

---

## Dependencies

Add to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_inappwebview: ^6.1.5
  flutter_secure_storage: ^9.2.2
  http: ^1.2.1
  crypto: ^3.0.3
```

```bash
flutter pub get
```

---

## Step 1 — Set Up the Redirect Server

SudaPass requires an HTTPS redirect URI. Your redirect server accepts the callback from SudaPass and fires a deep link back to your app.

### Production (your own domain)

On your server (nginx), create `/var/www/html/callback/index.html`:

```html
<!DOCTYPE html>
<html>
<head><title>Redirecting...</title></head>
<body>
<script>
  window.location.href = 'YOURAPP://callback' + window.location.search;
</script>
</body>
</html>
```

Create `/var/www/html/logout/index.html`:

```html
<!DOCTYPE html>
<html>
<head><title>Logged out</title></head>
<body>
<script>window.location.href = 'YOURAPP://logout';</script>
</body>
</html>
```

Replace `YOURAPP` with your app's custom URL scheme (e.g. `myapp`).

Your redirect URIs will be:
- `https://yourdomain.com/callback/`
- `https://yourdomain.com/logout/`

### Testing (ngrok)

```bash
ngrok http https://<your-server-ip>:443
```

Use the generated `https://xxxx.ngrok-free.app` URL as your domain. Note that this URL changes every time ngrok restarts — update your registered URIs in the SudaPass admin panel each session.

---

## Step 2 — Add the PKCE Helper

Create `lib/pkce.dart`:

```dart
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

class Pkce {
  static String generateVerifier() {
    final rand = Random.secure();
    final bytes = List<int>.generate(32, (_) => rand.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static String generateChallenge(String verifier) {
    final bytes = utf8.encode(verifier);
    final digest = sha256.convert(bytes);
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  static String randomString(int length) {
    final rand = Random.secure();
    final bytes = List<int>.generate(length, (_) => rand.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '').substring(0, length);
  }
}
```

---

## Step 3 — Add the Auth Service

Create `lib/auth_service.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'pkce.dart';

class AuthService {
  // ── Configure these for your app ──────────────────────────────────────────
  static const _clientId       = 'client_YOUR_CLIENT_ID';
  static const _redirectUri    = 'https://yourdomain.com/callback/';
  static const _postLogoutUri  = 'https://yourdomain.com/logout/';
  static const _callbackScheme = 'YOURAPP'; // must match your deep link scheme
  // ──────────────────────────────────────────────────────────────────────────

  static const _authorizeUrl  = 'https://sudapass.online/oauth/authorize';
  static const _tokenUrl      = 'https://sudapass.online/oauth/token';
  static const _endSessionUrl = 'https://sudapass.online/oauth/session/end';
  static const _scope         = 'openid profile email national_id';

  final _storage = const FlutterSecureStorage();

  /// Returns true on successful login, throws on failure.
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
```

---

## Step 4 — Register the Deep Link in AndroidManifest.xml

In `android/app/src/main/AndroidManifest.xml`, inside the `<activity>` block, add:

```xml
<!-- Deep link: receives callback from SudaPass -->
<intent-filter>
    <action android:name="android.intent.action.VIEW"/>
    <category android:name="android.intent.category.DEFAULT"/>
    <category android:name="android.intent.category.BROWSABLE"/>
    <data android:scheme="YOURAPP"/>
</intent-filter>
```

Also set `android:launchMode="singleTask"` on the `<activity>` tag to prevent duplicate instances on deep link.

---

## Step 5 — Trigger Login in Your App

```dart
final auth = AuthService();

try {
  final success = await auth.login();
  if (success) {
    // User is authenticated — navigate to your app's main screen
  }
} catch (e) {
  // Handle: user canceled, timeout, or auth failure
  print('Login failed: $e');
}
```

To check if the user is already logged in on app start:

```dart
final loggedIn = await auth.isLoggedIn();
```

To log out:

```dart
await auth.logout();
```

---

## Checklist

- [ ] Received `clientId` from NCTR
- [ ] Redirect URI registered in SudaPass admin panel (trailing slash must match exactly)
- [ ] nginx redirect server serving `/callback/` and `/logout/` pages
- [ ] `YOURAPP` scheme replaced with your actual app scheme in all files
- [ ] `android:launchMode="singleTask"` set on MainActivity

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `User canceled login` | Deep link not received. Test on a real device — emulators sometimes fail to handle custom schemes. |
| `Token exchange failed (400)` | Authorization code expired, or redirect URI mismatch. Ensure trailing slash is identical in `auth_service.dart`, nginx, and the SudaPass admin panel. |
| Blank page after redirect | ngrok interstitial is showing. Open the callback URL in a browser once and click "Visit Site" to bypass it. |
| `State mismatch` error | Do not reuse or cache the state value between sessions. Each login call generates a fresh one. |
| ngrok URL changed | Update `_redirectUri` and `_postLogoutUri` in `auth_service.dart` and re-register both URLs in the SudaPass admin panel. |
