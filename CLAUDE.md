# Anumati Collect: working notes for Claude Code

Flutter field app for Anumati (server: `sunandan89/anumati`, spec in its `docs/anumati-spec-v0.4.md`, prototype `docs/anumati-prototype.html` wins on UX and copy).

## Rules
- Use `frappe_mobile_sdk` for sign-in, session, API calls, uploads and the app-status guard. Don't re-implement what it has.
- Offline consent data lives in our own SQLCipher store (`lib/data/store.dart`), because the SDK's store is not encrypted. Evidence files are AES-GCM encrypted.
- Server rules stay on the server: the app calls the Anumati v1 API and stock Frappe endpoints only. No custom server endpoints for the app.
- The receipt code must match the server: `AN-` + base32(sha256(event_uuid)[:5])[:6]. Test vectors in `test/receipt_code_test.dart`.
- No PII in logs or error messages. All sample data is fictional.
- Text: English source strings in `lib/core/strings.dart`, Hindi alongside; server Translations override the bundled Hindi.
- Before pushing: `dart format lib test`, `flutter analyze`, `flutter test`.
