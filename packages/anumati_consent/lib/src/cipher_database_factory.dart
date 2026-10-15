import 'dart:typed_data';

import 'package:sqflite_sqlcipher/sqflite.dart' as cipher;

/// A [cipher.DatabaseFactory] that opens every database with SQLCipher and [password].
///
/// The Frappe Mobile SDK opens its one database through a `DatabaseFactory` and passes plain
/// `OpenDatabaseOptions` with its own schema callbacks. This factory keeps those callbacks and adds the
/// password, so the SDK's records, outbox and login token are encrypted on disk without any change to
/// the SDK. (Proposed upstream as a `FrappeSDK` setting; see docs/design/sdk-issues.md in the server repo.)
class CipherDatabaseFactory implements cipher.DatabaseFactory {
  CipherDatabaseFactory(this.password, {cipher.DatabaseFactory? delegate})
    : _delegate = delegate ?? cipher.databaseFactory;

  final String password;
  final cipher.DatabaseFactory _delegate;

  /// The options the delegate receives: the caller's, plus the password.
  static cipher.OpenDatabaseOptions withPassword(cipher.OpenDatabaseOptions? o, String password) =>
      cipher.SqlCipherOpenDatabaseOptions(
        version: o?.version,
        onConfigure: o?.onConfigure,
        onCreate: o?.onCreate,
        onUpgrade: o?.onUpgrade,
        onDowngrade: o?.onDowngrade,
        onOpen: o?.onOpen,
        readOnly: o?.readOnly ?? false,
        singleInstance: o?.singleInstance ?? true,
        password: password,
      );

  @override
  Future<cipher.Database> openDatabase(String path, {cipher.OpenDatabaseOptions? options}) =>
      _delegate.openDatabase(path, options: withPassword(options, password));

  @override
  Future<String> getDatabasesPath() => _delegate.getDatabasesPath();

  @override
  Future<void> setDatabasesPath(String path) => _delegate.setDatabasesPath(path);

  @override
  Future<void> deleteDatabase(String path) => _delegate.deleteDatabase(path);

  @override
  Future<bool> databaseExists(String path) => _delegate.databaseExists(path);

  @override
  Future<Uint8List> readDatabaseBytes(String path) => _delegate.readDatabaseBytes(path);

  @override
  Future<void> writeDatabaseBytes(String path, Uint8List bytes) => _delegate.writeDatabaseBytes(path, bytes);
}
