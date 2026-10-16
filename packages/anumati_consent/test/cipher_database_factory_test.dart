import 'dart:typed_data';

import 'package:anumati_consent/anumati_consent.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as cipher;

class RecordingFactory implements cipher.DatabaseFactory {
  cipher.OpenDatabaseOptions? options;

  @override
  Future<cipher.Database> openDatabase(String path, {cipher.OpenDatabaseOptions? options}) async {
    this.options = options;
    throw StateError('not opened in tests');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<String> getDatabasesPath() async => '/tmp';
  @override
  Future<void> setDatabasesPath(String path) async {}
  @override
  Future<void> deleteDatabase(String path) async {}
  @override
  Future<bool> databaseExists(String path) async => false;
  @override
  Future<Uint8List> readDatabaseBytes(String path) async => Uint8List(0);
  @override
  Future<void> writeDatabaseBytes(String path, Uint8List bytes) async {}
}

void main() {
  test("the SDK's schema callbacks are kept and the password is added", () async {
    Future<void> onCreate(cipher.Database db, int v) async {}
    Future<void> onConfigure(cipher.Database db) async {}
    final delegate = RecordingFactory();
    final factory = CipherDatabaseFactory('k3y', delegate: delegate);
    await expectLater(
      factory.openDatabase(
        'x.db',
        options: cipher.OpenDatabaseOptions(version: 7, onCreate: onCreate, onConfigure: onConfigure),
      ),
      throwsStateError,
    );
    final o = delegate.options!;
    expect(o, isA<cipher.SqlCipherOpenDatabaseOptions>());
    expect((o as cipher.SqlCipherOpenDatabaseOptions).password, 'k3y');
    expect(o.version, 7);
    expect(o.onCreate, same(onCreate));
    expect(o.onConfigure, same(onConfigure));
  });
}
