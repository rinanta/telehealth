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
registration; midwife applications are always created as pending until an
administrator verifies them in Firestore.

## Midtrans Sandbox payment setup

Payments use Midtrans Snap in Sandbox mode for this project. Only the backend
talks to Midtrans; Flutter never receives the Server Key.

1. Create a Midtrans account and switch the dashboard to **Sandbox**.
2. Copy the Sandbox Server Key from Settings → Access Keys into `backend/.env`:

   ```
   MIDTRANS_ENVIRONMENT=sandbox
   MIDTRANS_SERVER_KEY=SB-Mid-server-xxxxxxxx
   ```

3. Expose Laravel over public HTTPS (for example ngrok) and set the Midtrans
   Payment Notification URL to `https://<tunnel>/api/webhooks/midtrans`.
4. Use the Midtrans Sandbox payment methods. A booking becomes
   `paid_pending_midwife` only after Laravel verifies the signature, payment
   status, order ID, and amount.

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

The Flutter API base URL is configurable with `--dart-define=API_BASE_URL=...`.
For the currently running development tunnel, use:

```powershell
flutter run --dart-define=API_BASE_URL=https://<tunnel>/api
```

For a local Android emulator, use `http://10.0.2.2:8000/api`; for a physical
device on the same LAN, use the computer's LAN address.
