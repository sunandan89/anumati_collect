import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:frappe_mobile_sdk/frappe_mobile_sdk.dart';

import 'cipher_database_factory.dart';

const _keyName = 'anumati.sdk_db_key';

/// Opens the Frappe Mobile SDK's database encrypted with SQLCipher. Call it once, before the host's
/// `FrappeSDK.initialize()`, with the same name the host passes as `databaseAppName`.
///
/// The SDK keeps one database instance (`AppDatabase.getInstance`); opening it here first, through
/// the SDK's own `factoryResolver` hook, means the SDK uses this encrypted instance from then on. The
/// key is 32 random bytes made on first run and kept only in the phone's secure storage.
///
/// A phone that already has an unencrypted SDK database must start fresh (sign out, which clears it):
/// SQLCipher cannot open a plain file with a key.
Future<AppDatabase> openEncryptedSdkDatabase({
  required String appName,
  FlutterSecureStorage storage = const FlutterSecureStorage(),
}) async {
  final password = await databaseKey(storage);
  return AppDatabase.getInstance(appName: appName, factoryResolver: (_) async => CipherDatabaseFactory(password));
}

/// The database key, made on first use.
Future<String> databaseKey(FlutterSecureStorage storage) async {
  final existing = await storage.read(key: _keyName);
  if (existing != null && existing.isNotEmpty) return existing;
  final rnd = Random.secure();
  final key = base64UrlEncode(List<int>.generate(32, (_) => rnd.nextInt(256)));
  await storage.write(key: _keyName, value: key);
  return key;
}
