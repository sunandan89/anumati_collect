# Anumati Collect

The field app for [Anumati](https://github.com/sunandan89/anumati), the open-source DPDP consent platform for nonprofits. Field workers take consent offline, in Hindi or English, and the phone syncs to the organisation's own Anumati server, where every consent is signed and hash-chained.

Built with Flutter on Dhwani RIS's [frappe_mobile_sdk](https://github.com/dhwani-ris/frappe-mobile-sdk). Sign-in goes through [Frappe Mobile Control](https://github.com/dhwani-ris/frappe-mobile-control) on the server. MIT licence.

## What it does

| Screen | Spec |
|---|---|
| Home & sync: records waiting on the phone, programme, four field tasks | A5 |
| Beneficiary: ID, name, phone, segment flags, language | A6, C1, C2 |
| Guardian: type, verification by SMS code or document photo (minors and lawful guardians only) | C1, C2 |
| Notice: the live, reviewed notice; choices unlock after the audio plays through, or after reading to the end | A1, A3 |
| Choices: optional purposes start off; Yes to all and No to all carry equal weight; purposes not for minors are hidden | A4 |
| Evidence: her own choice on the phone, or voice clip, thumbprint photo and witness; the worker's attestation | A7 |
| Verify: SMS code from this phone (pre-filled SMS, never sent silently), confirm later, or evidence only, as the programme allows | Section 5 |
| Receipt: the consent code for her slip, computed on the phone so it's there before sync | B1, B4 |
| Log a withdrawal or request: in person, slip or letter; takes effect on the phone at once | B4, B5 |
| Ask for one more purpose: only the new purpose, earlier choices kept | A2, A4 |
| Find beneficiary: offline search by name, ID or code, with each purpose's status | |

## Security on the phone

- Names, phone numbers and the outbox are in an **SQLCipher** database. Evidence (voice clips, photos) is encrypted with **AES-256-GCM**. Both keys are generated on the phone and kept in the Android Keystore.
- Screenshots and screen recording are blocked. Android backup and device transfer are off.
- Signing out wipes the database, the evidence and both keys.
- Nothing personal is logged. The server never echoes names or numbers back.

## Sync

The outbox sends records oldest first, through the Anumati v1 API (`principal.upsert`, `consent.record`, `consent.withdraw`, `rights.submit`) and stock Frappe endpoints (file upload, Guardian Link). Every step is idempotent: a sync cut off halfway picks up where it stopped, and the server returns the original signed record if the same event arrives twice. Records the server refuses are listed under **Needs attention** with the server's reason.

## Build

CI (`.github/workflows/ci.yml`) runs format, analyze and tests, then builds an APK on every push. Download it from the run's **Artifacts**. Signed Play bundles are built once the upload key exists; see [docs/play-store.md](docs/play-store.md).

## Server setup

See section F of the Anumati [setup guide](https://github.com/sunandan89/anumati/blob/main/docs/setup-guide.md): add Frappe Mobile Control to the bench, switch on Mobile Configuration (package `org.anumati.collect`), and give field workers the **Anumati Field Worker** and **Mobile User** roles.
