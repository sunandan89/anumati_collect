/// Anumati consent capture on a host app's Frappe Mobile SDK.
///
/// The package never creates its own SDK, database, outbox or sync: it attaches to the host's
/// `FrappeSDK` and saves consent as ordinary DocType records, which the SDK stores, queues and pushes.
/// The server's Consent Event DocType checks, signs and chains each one.
library;

export 'src/anumati_consent.dart';
export 'src/cipher_database_factory.dart';
export 'src/consent_data.dart';
export 'src/encrypted_sdk_database.dart';
export 'src/receipt_code.dart';
