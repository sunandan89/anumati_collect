# anumati_consent

Anumati consent capture as a Flutter package that runs on a host app's
[Frappe Mobile SDK](https://github.com/dhwani-ris/frappe-mobile-sdk). Spike: proves the data path of
the revised architecture before the screens move over.

- **No own data layer.** It attaches to the host's `FrappeSDK` and saves each decision as a
  `Consent Event` record through the SDK's offline repository. The SDK's outbox and sync push it as a
  standard insert. No custom endpoint is called.
- **Rules on the server.** The Consent Event DocType checks purposes, who may consent, the notice and
  evidence, sets the verification status, and signs and chains the record. The phone never sends a
  verification status.
- **Encrypted on the phone.** `openEncryptedSdkDatabase` opens the SDK's database with SQLCipher through
  the SDK's own database hook, before `FrappeSDK.initialize()`. Records, outbox and the login token are
  all in that file.
- **Receipt code offline.** The record's `mobile_uuid` is its event ID, so the code on the slip
  (`AN-XXXXXX`) is known before sync and matches the server's.

```dart
await openEncryptedSdkDatabase(appName: 'anumati_collect');   // before initialize
final sdk = FrappeSDK(baseUrl: url, databaseAppName: 'anumati_collect');
await sdk.initialize();
final consent = AnumatiConsent.attach(sdk);
final receipt = await consent.record(ConsentDecision(
  principal: 'DP-00017', programme: 'MCH', granted: ['screen'], denied: ['photos'],
  verificationMethod: 'deferred'));
print(receipt.code); // write it on the slip
```

**Server set-up:** in Mobile Configuration, add Consent Event (and Consent State, Programme, Purpose,
Notice Template for downloads) to the mobile forms, so Mobile Control adds the `mobile_uuid` field and
the SDK syncs them.

**Not yet:** people's names and phones (the SDK skips encrypted fields until the "personal fields"
contribution lands), encrypted photo and voice files before upload, and the screens.
