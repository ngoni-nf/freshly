# Firebase

Firebase does two separate jobs here, and they fail independently:

- **Phone sign-in.** The apps get a Firebase ID token, the API verifies it and
  issues its own JWT. Firebase proves who owns a number; it never decides who
  is a verified provider. Controlled by `FIREBASE_ENABLED`.
- **Push.** Dispatch offers reach a backgrounded app only through FCM.
  Controlled by `PUSH_ENABLED`.

Both read the same project and the same service account. Either can be off.

Project: **`freshly-146c6`**.

---

## 1. Register the two Android apps

They are separate apps in Firebase, because they are separate installs with
separate tokens:

| App | Package name |
|---|---|
| Freshly (client) | `africa.freshly.client` |
| Freshly Partner | `africa.freshly.partner` |

The package name must match `applicationId` in
`apps/mobile_*/android/app/build.gradle.kts` exactly. It cannot be changed
after registration — you would add a new app instead.

Either register them in the console, or:

```bash
firebase apps:create android "Freshly Client" --package-name africa.freshly.client --project freshly-146c6
```

```bash
firebase apps:create android "Freshly Partner" --package-name africa.freshly.partner --project freshly-146c6
```

### If the CLI says the project does not exist

`firebase projects:list` shows only projects the **logged-in CLI account** can
see, which is not necessarily the account in your browser. Check with
`firebase login:list`. To add the right one:

```bash
firebase login:add
```

That opens a browser and needs an interactive terminal — it refuses to run
under automation. Then `firebase login:use <email>`.

## 2. Download the config files

```bash
firebase apps:sdkconfig android <APP_ID> --project freshly-146c6 --out apps/mobile_client/android/app/google-services.json
```

`<APP_ID>` comes from `firebase apps:list --project freshly-146c6` and looks
like `1:123456789:android:abc123`. Repeat for the partner app.

They must land at exactly:

```
apps/mobile_client/android/app/google-services.json
apps/mobile_partner/android/app/google-services.json
```

**Neither is committed** — `.gitignore` covers them. Every developer and every
CI runner needs its own copy. Without them the build fails at
`:app:processDebugGoogleServices` with "File google-services.json is missing",
which is the Google Services Gradle plugin, not Flutter.

## 3. Turn on the products

In the console:

- **Authentication → Sign-in method → Phone.** Add the demo numbers under
  "Phone numbers for testing" so QA does not burn real SMS quota.
- **Cloud Messaging.** Enabled by default; nothing to do.
- **Crashlytics.** Shows no data until the first crash from a real build.

## 4. Give the API a service account

Console → Project settings → Service accounts → Generate new private key.
This downloads a JSON file. It is a credential for the whole project:

```
FIREBASE_ENABLED=true
PUSH_ENABLED=true
FIREBASE_PROJECT_ID=freshly-146c6
FIREBASE_SERVICE_ACCOUNT_JSON={"type":"service_account",...}
```

Paste the JSON on one line, or point `GOOGLE_APPLICATION_CREDENTIALS` at the
file instead. Never commit either. On Fly it is `fly secrets set`.

`nest --watch` does not restart on `.env` changes — restart the API by hand.

## 5. Check it end to end

The failure mode to rule out is a push that is accepted by Google and never
arrives, so test against a **backgrounded** app, not a foregrounded one. The
websocket covers the foreground and will make a broken push look like it works.

1. Sign in on the partner app so a device row is written.
2. Background it. Do not just lock the screen — swipe away to the launcher.
3. Create a booking from the client app.
4. The offer notification should appear within a second or two.

If nothing arrives, in order:

```sql
SELECT user_id, platform, left(push_token, 12) FROM devices;
```

- No row: the app never sent a token. Check notification permission was granted
  (Android 13+ needs `POST_NOTIFICATIONS` at runtime, not just in the manifest).
- A row but no delivery: check the API log for `push send failed`, and confirm
  `PUSH_ENABLED=true` actually reached the process.
- Delivered but no heads-up alert: the channel. The API sends
  `freshly_dispatch` for offers and `freshly_bookings` for everything else, and
  those ids must match what the app registers. Android silently drops an unknown
  channel to default importance, which costs exactly the alert you wanted.

## What is still missing on the app side

The manifests declare the two channels, but neither app creates them at
`IMPORTANCE_HIGH`. Until one does, an offer arrives as a silent notification
rather than a heads-up alert — delivered, but easy to miss, which defeats most
of the point. That needs `flutter_local_notifications` (or a platform channel)
creating `freshly_dispatch` and `freshly_bookings` at startup.

## iOS

Not done. It additionally needs an APNs key uploaded to Firebase under Cloud
Messaging, and a `GoogleService-Info.plist` per app. Push does not work on the
iOS simulator at all — it needs a real device.
