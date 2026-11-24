# Planova

Simple Flutter planner for web, Android phones/tablets, and iPhone/iPad. Production hosting uses GitHub Pages and Supabase; the Node/SQLite server remains available for isolated local development and tests.

## Production hosting: GitHub Pages + Supabase

The production architecture is:

- GitHub Pages serves the compiled Flutter website.
- Supabase Auth provides password accounts, email confirmation codes, sign-in codes, and password recovery.
- Supabase Postgres stores profiles, settings, and plans behind owner-only Row Level Security policies.
- The authenticated `planova-api` Edge Function validates planner requests and calls Gemini without exposing the Gemini key.

Create a Supabase project, then deploy the database and function from this repository:

```powershell
npx supabase login
npx supabase link --project-ref YOUR_PROJECT_REF
npx supabase db push
npx supabase secrets set GEMINI_API_KEY=YOUR_NEW_KEY GEMINI_MODEL=gemini-2.5-flash ALLOWED_ORIGINS=https://YOUR_GITHUB_USER.github.io
npx supabase functions deploy planova-api
```

In Supabase Auth, enable email/password sign-in and change the confirmation and magic-link email templates to show `{{ .Token }}` so users receive the six-digit code expected by Planova. Add the final GitHub Pages URL to Auth URL Configuration. The SQL migration in `supabase/migrations` enables RLS and restricts every row to its authenticated owner.

Create a GitHub repository and add repository secrets named `SUPABASE_URL` and `SUPABASE_ANON_KEY` (use the public publishable/anon key, never the service-role key). Enable **Settings > Pages > Source: GitHub Actions**. Pushing `main` runs analysis, all Flutter tests, builds with the correct Pages base path, and deploys through `.github/workflows/pages.yml`.

The bundled Manrope and DM Serif Display fonts are covered by the SIL Open Font License files in `assets/fonts`; no font request is made at runtime.

## Start the website

Requirements: Flutter/Dart compatible with pubspec.yaml, Node 22.13+, and JDK 17+ for Android.

```powershell
flutter pub get
npm.cmd ci --prefix server
.\scripts\run_web.ps1
```

Open http://localhost:8787. To start the existing web build without rebuilding, run `.\scripts\run_server.ps1`. Keep the server running while using the website or apps. Restart it after changing the root `.env`.

## Shared API key and SMTP

Only the root `.env` (beside pubspec.yaml) contains secrets. It is ignored by Git and is never packaged in Flutter or served as a website asset. `.env.example` is the shareable template.

```dotenv
GEMINI_API_KEY=your_key
GEMINI_MODEL=gemini-3.5-flash-lite
PLANNER_HOST=127.0.0.1
PLANNER_PORT=8787
PLANNER_ALLOWED_ORIGINS=http://localhost:8787,http://127.0.0.1:8787
PLANNER_LAN_HOST=
SMTP_HOST=smtp.gmail.com
SMTP_PORT=465
SMTP_SECURE=true
SMTP_USER=your_email@gmail.com
SMTP_PASS=your_app_password
SMTP_FROM=your_email@gmail.com
COOKIE_SECURE=false
```

For Gmail, use a [Google App Password](https://support.google.com/accounts/answer/185833) with 2-Step Verification enabled. This is the sender account; users register with their own email addresses. Keep credentials out of config/client.json.

```powershell
node server/check-smtp.mjs
```

This verifies TLS and SMTP authentication without sending email. To verify inbox delivery, request an OTP through the app and check inbox/spam.

## Create account, sign in and recover a password

Choose **Create account**, enter your name, email and a password with 12 to 128 characters, then confirm the emailed six-digit code. Sign-in requires the email/password and another email code. Passwords are salted and hashed with scrypt (N=32768, r=8, p=3); plaintext passwords are never saved. These parameters follow [OWASP password-storage guidance](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html#scrypt).

Use **Forgot password?** to request a reset code. Enter that code and confirm a new password. Reset codes expire in 10 minutes, allow five attempts and can be requested again after 60 seconds. Successful reset invalidates all account sessions and pending codes, sends a password-change notice and returns to normal sign-in. See [OWASP recovery guidance](https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html).

Existing OTP-only accounts and their plans are preserved. Use Forgot password, or Profile > Reset password while signed in, to set the first password for an existing account. Updating the app is required for the new password-based sign-in flow.

Browser sessions use HttpOnly, SameSite=Strict cookies. Native tokens use Android encrypted storage / iOS Keychain. Sessions expire after seven days; signing out revokes that device's session. Registration, sign-in and recovery are rate limited. Missing SMTP configuration produces an error; there is no fake OTP or sign-in bypass.

## Profile avatar

Open **Profile > Customize avatar** to choose initials or an icon and a background color, then Save avatar. Or open **Profile > Change photo** and choose a JPG, PNG or WebP photo. Photos are limited to 2 MB, decoded and cropped to a 256-pixel square, converted to JPEG with metadata removed, and stored privately with the account in the server database. Remove photo restores initials. The avatar refreshes on other signed-in devices with the profile sync. Profile also shows the account email and a Reset password action.

## Automatic generation

1. Choose a date and **Plan this day**.
2. Add tasks. Set durations or leave **Auto estimate**.
3. Set a start time and breaks.
4. Tap **Generate plan**. The plan saves automatically and opens **Tasks**. The schedule also appears on Home.

Generation automatically uses the server's configured Gemini key. There is no provider switch or key input in the interface. Explicit durations are preserved, invalid results are rejected, and failed generation does not overwrite saved plans.

Only validated task details go to Google's planning API. SMTP credentials and session tokens are not sent to Google. See [Google's key guidance](https://ai.google.dev/gemini-api/docs/api-key#security).

## Feedback and APK download

The **Feedback** page stores a category, recommendation response, and visibility choice with each authenticated submission. Feedback is private unless the user opts in to sharing it; only public submissions appear in Community Feedback. Authors can edit or delete their own entries, and likes are unique per user and entry. Supabase RLS protects the hosted records; the local account API applies the same ownership and visibility rules.

The Home screen's **Download APK** button opens the public Google Drive folder configured by `APK_DOWNLOAD_URL`. The default is the project's shared APK folder; use a different HTTPS URL with `--dart-define=APK_DOWNLOAD_URL=...` when building if needed. The Drive folder must allow access to anyone with its link.

## Layout and account sync

The desktop website uses a charcoal and cream ribbon with a central Planova badge. Mobile and tablet browser widths below 900 pixels, and native phone and tablet apps, use a floating dark bottom navigation bar with a white active tab. The Planova name is shared across the website, app launcher and OTP emails.

In production, data lives in Supabase Postgres with owner-only RLS. The local Node development server stores isolated local data in `server/data/accounts.db`. Sign in with the same account on each device to share plans and completion. Clients refresh every 45 seconds and when resumed. Version checks prevent stale devices from silently overwriting newer plans. After a conflict, reopen the draft after automatic sync. Server access is required; there is no offline write queue.

The earlier anonymous local SQLite/IndexedDB database is preserved. Its records are not automatically attached to a new account. Back up the account database with its `auth-secret`; keep both private.

## Android phone/tablet on the same Wi-Fi

```powershell
node scripts/configure-lan.mjs
# Restart the server after this step.
.\scripts\build_android.ps1
```

The helper chooses the private Wi-Fi address, adds PLANNER_LAN_HOST to .env, and places the public endpoint in config/client.json. The server listens on localhost and that private interface. The APK is `build/releases/Planova-1.1.0-debug.apk`. Keep the phone and PC on the same Wi-Fi. Windows Firewall must allow Node on your private network.

If the PC's IP changes, run the helper again, restart the server and rebuild. The debug APK permits local HTTP. Release apps require HTTPS. Android minimum SDK is 23.

For an emulator, clear NATIVE_API_URL to use Android's default 10.0.2.2:8787; iOS simulator defaults to 127.0.0.1:8787.

## iOS deployment

iPhone/iPad use the same Flutter login, planning and sync code. [iOS builds require macOS and Xcode](https://docs.flutter.dev/deployment/ios); a signed IPA cannot be generated on Windows.

On a Mac:

```bash
bash scripts/build_ios.sh
```

Open ios/Runner.xcworkspace in Xcode, select a signing team and run on a device. Debug uses Info-Debug.plist to permit local HTTP. Release uses Info.plist with HTTPS.

Build Android and iOS releases with the same public `SUPABASE_URL` and publishable key used by the website. Store the Gemini key only in the Supabase Edge Function secret. App-store publication remains a separate signed release step.

## Verification

```powershell
flutter analyze --no-pub
flutter test --no-pub
node --test server/auth.test.mjs server/planner-store.test.mjs server/server.test.mjs server/accounts-http.test.mjs server/web-cache.test.mjs server/passwords.test.mjs server/avatar.test.mjs
.\scripts\build_web.ps1 -NoPub
node scripts/check_web.mjs
.\scripts\build_android.ps1
```

Tests use isolated data, fake email delivery and mocked Gemini responses. The browser check uses a temporary account server, fake SMTP and hidden Chrome. It verifies password + OTP sign-in, recovery and photo upload, and saves screenshots under build/previews. It does not create production accounts or send email.

`node server/check-gemini.mjs` is a separate manual check that makes one small billable Gemini request using the configured key.

On this machine Android Studio's Java runtime is incomplete. A verified local Temurin JDK 17 is under build/tools/java17; the Android helper uses it without changing system Java. Pass -JdkPath to use another JDK. Flutter clean removes this project-local JDK.

Web updates are served with no-store headers. The custom bootstrap retires the legacy Flutter service worker and its UI caches; account cookies and local databases are preserved. Android builds use the version in pubspec.yaml and save a versioned APK under build/releases so the new installer is easy to identify.

Use scripts/build_web.ps1 to build the website. It regenerates Flutter 3.32 web plugin registration so added plugins, including the photo picker, are not omitted by a stale entry-point cache.
