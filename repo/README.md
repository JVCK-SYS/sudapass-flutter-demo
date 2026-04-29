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
  flutter_secure_storage: ^9.0.0
  http: ^1.2.0
  crypto: ^3.0.3
```

```bash
flutter pub get
```

---

## Step 1 — Set Up the Redirect Server

SudaPass requires an HTTPS redirect URI. When SudaPass sends the user back after authentication, the redirect page fires a deep link that opens your app.

You have three options:

### Option A — GitHub Pages (recommended)

Free, permanent, no server required.

**1. Create a new public GitHub repo** (e.g. `myapp-sudapass`)

**2. Create these files in the repo:**

`callback/index.html`
```html
<!DOCTYPE html>
<html>
<head><title>Redirecting...</title></head>
<body>
<script>
  window.location.replace('https://YOUR_GITHUB_USERNAME.github.io/YOUR_REPO_NAME/callback/' + window.location.search);
</script>
<p>Redirecting back to app... <a id="btn" href="#">Tap here if not redirected</a></p>
<script>
  document.getElementById('btn').href =
    'https://YOUR_GITHUB_USERNAME.github.io/YOUR_REPO_NAME/callback/' + window.location.search;
</script>
</body>
</html>
```

`logout/index.html`
```html
<!DOCTYPE html>
<html>
<head><title>Logged out</title></head>
<body>
<script>
  window.location.replace('https://YOUR_GITHUB_USERNAME.github.io/YOUR_REPO_NAME/logout');
</script>
</body>
</html>
```

`.well-known/assetlinks.json`
```json
[{
  "relation": ["delegate_permission/common.handle_all_urls"],
  "target": {
    "namespace": "android_app",
    "package_name": "YOUR_APP_PACKAGE_NAME",
    "sha256_cert_fingerprints": [
      "YOUR_APP_SHA256_FINGERPRINT"
    ]
  }
}]
```

`.nojekyll` (empty file — required so GitHub Pages serves `.well-known`)

`index.html` (root — required to activate GitHub Pages)
```html
<!DOCTYPE html>
<html><head><title>SudaPass Integration</title></head><body></body></html>
```

**3. Enable GitHub Pages:**
- Repo Settings → Pages → Source: Deploy from branch → `main` → `/ (root)` → Save

**4. Your redirect URIs will be:**
- `https://YOUR_GITHUB_USERNAME.github.io/YOUR_REPO_NAME/callback/`
- `https://YOUR_GITHUB_USERNAME.github.io/YOUR_REPO_NAME/logout/`

**Get your SHA256 fingerprint:**
```bash
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
```
Copy the `SHA256` value from the output.

---

### Option B — Your Own Domain (production)

On your nginx server, create `/var/www/html/callback/index.html`:

```html
<!DOCTYPE html>
<html>
<head><title>Redirecting...</title></head>
<body>
<script>
  window.location.replace('https://yourdomain.com/callback/' + window.location.search);
</script>
</body>
</html>
```

And `/var/www/html/logout/index.html`:

```html
<!DOCTYPE html>
<html>
<head><title>Logged out</title></head>
<body>
<script>window.location.replace('https://yourdomain.com/logout');</script>
</body>
</html>
```

Host `assetlinks.json` at `https://yourdomain.com/.well-known/assetlinks.json` with the same content as above.

---

### Option C — ngrok (local testing only)

```bash
ngrok http https://<your-server-ip>:443
```

Use the generated URL as your domain. Note: the URL changes every ngrok restart — update your registered URIs in the SudaPass admin panel each session.

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

Create `lib/auth_service.dart` and fill in your values:

```dart
// Option A — GitHub Pages
static const _clientId       = 'client_YOUR_CLIENT_ID';
static const _redirectUri    = 'https://YOUR_GITHUB_USERNAME.github.io/YOUR_REPO_NAME/callback/';
static const _postLogoutUri  = 'https://YOUR_GITHUB_USERNAME.github.io/YOUR_REPO_NAME/logout/';
static const _callbackScheme = 'https';
```

See `lib/auth_service.dart` in this repo for the full implementation.

---

## Step 4 — Configure AndroidManifest.xml

In `android/app/src/main/AndroidManifest.xml`, add inside the `<activity>` block:

```xml
<!-- App Links: GitHub Pages callback -->
<intent-filter android:autoVerify="true">
    <action android:name="android.intent.action.VIEW"/>
    <category android:name="android.intent.category.DEFAULT"/>
    <category android:name="android.intent.category.BROWSABLE"/>
    <data android:scheme="https"
          android:host="YOUR_GITHUB_USERNAME.github.io"
          android:pathPrefix="/YOUR_REPO_NAME/callback"/>
</intent-filter>

<!-- App Links: GitHub Pages logout -->
<intent-filter android:autoVerify="true">
    <action android:name="android.intent.action.VIEW"/>
    <category android:name="android.intent.category.DEFAULT"/>
    <category android:name="android.intent.category.BROWSABLE"/>
    <data android:scheme="https"
          android:host="YOUR_GITHUB_USERNAME.github.io"
          android:pathPrefix="/YOUR_REPO_NAME/logout"/>
</intent-filter>
```

Also set `android:launchMode="singleTask"` on the `<activity>` tag.

---

## Step 5 — Register URIs in SudaPass Admin Panel

| Field | Value |
|---|---|
| Redirect URI | `https://YOUR_GITHUB_USERNAME.github.io/YOUR_REPO_NAME/callback/` |
| Post-logout URI | `https://YOUR_GITHUB_USERNAME.github.io/YOUR_REPO_NAME/logout/` |

---

## Step 6 — Trigger Login in Your App

```dart
final auth = AuthService();

try {
  final user = await auth.login();

  // Citizen identity is now available:
  print(user.name);           // "Ahmed Mohamed"
  print(user.nationalNumber); // "123456789"
  print(user.email);          // "ahmed@example.com"
  print(user.gender);         // "M"
  print(user.birthdate);      // "1990-01-01"
  print(user.nationality);    // "Sudanese"
  print(user.picture);        // URL or path to citizen photo
  print(user.assuranceLevel); // "urn:sudapass:fido2"
  print(user.raw);            // full JSON response as Map

  // Navigate to your main screen and use the data however you need
} catch (e) {
  print('Login failed: $e');
}
```

Retrieve the user later without triggering a new login:

```dart
final user = await auth.getUser(); // returns SudaPassUser? or null if not logged in
```

Check session on app start:

```dart
final loggedIn = await auth.isLoggedIn();
```

Log out:

```dart
await auth.logout();
```

---

## Real Device vs Emulator

| | Real Device | Emulator |
|---|---|---|
| App Links auto-intercept | ✅ Works | ❌ Does not work |
| APK to use | `app-arm64-v8a-debug.apk` | `app-x86_64-debug.apk` |
| Callback behavior | Opens app automatically | Opens browser — tap the link on the page |

Build both:
```bash
flutter build apk --debug --split-per-abi
```

---

## Checklist

- [ ] Client ID received from NCTR
- [ ] GitHub Pages repo created with `callback/`, `logout/`, `.well-known/assetlinks.json`, `.nojekyll`, `index.html`
- [ ] GitHub Pages enabled in repo settings
- [ ] SHA256 fingerprint added to `assetlinks.json`
- [ ] Redirect URIs registered in SudaPass admin panel (trailing slash must match exactly)
- [ ] `android:launchMode="singleTask"` set on MainActivity
- [ ] App Links verified: open `https://YOUR_GITHUB_USERNAME.github.io/YOUR_REPO_NAME/callback/?code=test&state=test` in phone browser — it should open the app directly

---

## Troubleshooting

| Problem | Fix |
|---|---|
| Callback opens browser instead of app | App Links not verified yet. Wait a few minutes after setup, or test the assetlinks.json URL directly. |
| `Token exchange failed (400)` | Redirect URI mismatch. Ensure trailing slash is identical in `auth_service.dart`, GitHub Pages, and SudaPass admin panel. |
| `State mismatch` error | Do not reuse state between sessions — each `login()` call generates a fresh one automatically. |
| `.well-known` returns 404 | Make sure `.nojekyll` file exists in the repo root. |
| App Links not intercepting on emulator | Expected — use the tap-the-link workaround on emulators. |
