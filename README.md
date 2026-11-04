# TeleBunda AI

Flutter Android app and Laravel API in one repository. The approved product scope
and acceptance criteria are in [PRD_TeleBunda_AI_MVP.md](./PRD_TeleBunda_AI_MVP.md).

## Firebase authentication setup

1. In Firebase Console, enable **Authentication → Email/Password**.
2. Keep the Android app configuration at `android/app/google-services.json`.
   It must match the app ID configured in `android/app/build.gradle.kts`.
3. Configure `FIREBASE_PROJECT_ID` in `backend/.env`.
4. Create a Firebase service-account key in Firebase Console and save it locally
   as `backend/storage/app/private/firebase-service-account.json`. Set
   `FIREBASE_CREDENTIALS` in `backend/.env` if you use a different path.
   Never commit or share this service-account file.
5. Start Laravel with `cd backend; php artisan serve --host 0.0.0.0`.

The app authenticates with Firebase, then sends its Firebase ID token as a
Bearer token to Laravel. Laravel verifies the token and reads/writes user
profiles in Firestore through its REST API. Patient profiles are verified at
registration; midwife applications are always created as pending. The demo
account presets remain available in debug builds and do not authenticate with
the backend.

## Midtrans Sandbox payment setup

Payments use Midtrans Snap (redirect). Only the backend talks to Midtrans.

1. Create a Midtrans account and switch the dashboard to **Sandbox**.
2. Copy the Sandbox **Server Key** (`SB-Mid-server-...`) from
   Settings → Access Keys into `backend/.env`:

   ```
   MIDTRANS_ENVIRONMENT=sandbox
   MIDTRANS_SERVER_KEY=SB-Mid-server-xxxxxxxx
   ```

3. Expose Laravel over public HTTPS (for example a Cloudflare Tunnel or ngrok)
   and set **Settings → Configuration → Payment Notification URL** to
   `https://<your-tunnel>/api/webhooks/midtrans`.
4. Pay with the Midtrans Sandbox simulators (virtual account, QRIS, GoPay,
   test cards). The booking only becomes `paid_pending_midwife` after the
   backend verifies the notification signature and the transaction status.

## Local checks

From the repository root:

```powershell
flutter analyze
flutter test
```

From `backend`:

```powershell
composer install
php artisan test
```

For Android emulator testing, the API base URL uses `10.0.2.2:8000` to reach
Laravel on the development machine.
