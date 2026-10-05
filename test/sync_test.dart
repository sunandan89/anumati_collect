import 'dart:io';

import 'package:anumati_collect/data/server.dart';
import 'package:anumati_collect/data/store.dart';
import 'package:anumati_collect/data/sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frappe_mobile_sdk/frappe_mobile_sdk.dart'
    show ValidationException, AuthException, NetworkException, ApiException;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A fake server that records calls and can fail on demand. Sample data is fictional.
class FakeServer implements Server {
  final calls = <String>[];
  final principals = <String, Map<String, dynamic>>{};
  final events = <String, Map<String, dynamic>>{};
  final links = <String, Map<String, dynamic>>{};
  final uploads = <String>[];
  final failNext = <String, Failure>{};

  void _maybeFail(String call) {
    final f = failNext.remove(call);
    if (f != null) throw ServerFailure(f, '$call failed');
  }

  @override
  Future<void> upsertPrincipal(Map<String, dynamic> values) async {
    calls.add('upsert');
    _maybeFail('upsert');
    principals[values['principal_ref'] as String] = values;
  }

  @override
  Future<String?> principalName(String ref) async => principals.containsKey(ref) ? 'dp-$ref' : null;

  final told = <String>[];

  @override
  Future<Map<String, dynamic>> sendCode(String consentId) async => {'sent': true, 'to': '9000011XXX'};

  @override
  Future<Map<String, dynamic>> checkCode(String consentId, String code) async => {'confirmed': code == '123456'};

  @override
  Future<void> guardianNeeded(String programme) async {
    calls.add('guardian_needed');
    told.add(programme);
  }

  @override
  Future<String> guardianLink(Map<String, dynamic> doc) async {
    calls.add('link');
    final key = '${doc['principal']}|${doc['guardian']}';
    links.putIfAbsent(key, () => doc);
    return 'GL-$key';
  }

  @override
  Future<String> uploadEvidence(File file, String principalName, String fileName) async {
    calls.add('upload');
    _maybeFail('upload');
    uploads.add(await file.readAsString());
    return '/private/files/$fileName';
  }

  @override
  Future<Map<String, dynamic>> record(Map<String, dynamic> event) async {
    calls.add('record');
    _maybeFail('record');
    final uuid = event['event_uuid'] as String;
    events.putIfAbsent(uuid, () => event);
    return {'consent_id': uuid, 'short_code': 'AN-SERVER'};
  }

  @override
  Future<Map<String, dynamic>> withdraw(Map<String, dynamic> args) async {
    calls.add('withdraw');
    _maybeFail('withdraw');
    return {'short_code': 'AN-W'};
  }

  @override
  Future<Map<String, dynamic>> submitRequest(Map<String, dynamic> args) async {
    calls.add('request');
    return {'request': 'RQ-00001'};
  }

  Map<String, dynamic>? people;
  @override
  Future<Map<String, dynamic>?> peopleForDevice(String programme, String? since) async => people;
  @override
  Future<Map<String, dynamic>?> registerDevice(
    String deviceId, {
    String? appVersion,
    String? model,
    int pending = 0,
  }) async => {'status': 'active', 'wipe': false};

  @override
  Future<Map<String, dynamic>?> hear(List<int> clip, String? language) async => null;

  @override
  Future<List<Map<String, dynamic>>> programmes() async => [];
  @override
  Future<Map<String, dynamic>> programme(String code) async => {};
  @override
  Future<Map<String, dynamic>> activeNotice(String programme, String? language) async => {};
  @override
  Future<File?> download(String fileUrl, File to) async => null;
}

Map<String, dynamic> consentPayload(String uuid, {List<Map<String, String>> evidence = const [], Map? guardian}) => {
  'principal': {'principal_ref': 'MHU-1', 'full_name': 'Meena K. (fictional)', 'phone': '9000011111'},
  'guardian': ?guardian,
  'evidence': evidence,
  'event': {
    'event_uuid': uuid,
    'principal_ref': 'MHU-1',
    'programme': 'MHU',
    'purposes_granted': ['screen'],
  },
};

void main() {
  late Store store;
  late FakeServer server;
  late Syncer syncer;
  late Directory tmp;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('anumati_test');
    final evDir = Directory('${tmp.path}/evidence')..createSync();
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1, onCreate: (db, _) => Store.createSchema(db)),
    );
    store = Store(db, files: EvidenceFiles(evDir, List.generate(32, (i) => i)));
    server = FakeServer();
    syncer = Syncer(store, server, tmp);
  });

  tearDown(() async {
    await store.db.close();
    await tmp.delete(recursive: true);
  });

  Future<Map<String, String>> evidence(String text) async {
    final f = File('${tmp.path}/voice.txt')..writeAsStringSync(text);
    final (id, sha) = await store.files!.adopt(f, 'm4a');
    expect(f.existsSync(), isFalse, reason: 'plaintext is deleted after encryption');
    return {'local': id, 'kind': 'audio', 'sha256': sha};
  }

  test('evidence is encrypted at rest and decrypts for upload', () async {
    final ev = await evidence('fictional voice clip');
    final onDisk = File('${store.files!.dir.path}/${ev['local']}').readAsBytesSync();
    expect(String.fromCharCodes(onDisk).contains('fictional voice clip'), isFalse);
    final plain = await store.files!.reveal(ev['local']!, tmp);
    expect(plain.readAsStringSync(), 'fictional voice clip');
  });

  test('a consent with evidence syncs once, carries file hashes, then evidence is removed', () async {
    final ev = await evidence('clip');
    await store.enqueue(
      kind: 'consent',
      eventUuid: 'u-1',
      principalRef: 'MHU-1',
      payload: consentPayload('u-1', evidence: [ev]),
    );
    final r = await syncer.run();
    expect(r.synced, 1);
    expect(server.calls, ['upsert', 'upload', 'record']);
    final sent = server.events['u-1']!;
    expect((sent['evidence'] as List).single['sha256'], ev['sha256']);
    expect((sent['evidence'] as List).single['file'], startsWith('/private/files/u-1-audio'));
    expect(File('${store.files!.dir.path}/${ev['local']}').existsSync(), isFalse);
    expect(await store.count('pending'), 0);
    expect((await syncer.run()).synced, 0, reason: 'nothing left to send');
  });

  test('a sync cut off halfway resumes without repeating finished steps', () async {
    final ev = await evidence('clip');
    await store.enqueue(
      kind: 'consent',
      eventUuid: 'u-2',
      principalRef: 'MHU-1',
      payload: consentPayload('u-2', evidence: [ev]),
    );
    server.failNext['record'] = Failure.offline;
    final first = await syncer.run();
    expect(first.stoppedBy, Failure.offline);
    expect(await store.count('pending'), 1);
    final second = await syncer.run();
    expect(second.synced, 1);
    expect(server.calls.where((c) => c == 'upload').length, 1, reason: 'uploaded once');
    expect(server.calls.where((c) => c == 'upsert').length, 1, reason: 'principal upserted once');
    expect(server.calls.where((c) => c == 'record').length, 2);
  });

  test('a rejected record is parked with its reason and the rest still sync', () async {
    await store.enqueue(kind: 'consent', eventUuid: 'u-3', principalRef: 'MHU-1', payload: consentPayload('u-3'));
    await store.enqueue(
      kind: 'request',
      payload: {
        'args': {'request_type': 'access', 'channel': 'field_worker'},
      },
    );
    server.failNext['record'] = Failure.rejected;
    final r = await syncer.run();
    expect(r.failed, 1);
    expect(r.synced, 1);
    final failed = await store.failed();
    expect(failed.single.error, 'record failed');
    await store.retry(failed.single.id);
    expect((await syncer.run()).synced, 1);
  });

  test('an expired login stops the run and keeps everything pending', () async {
    await store.enqueue(
      kind: 'withdraw',
      eventUuid: 'w-1',
      payload: {
        'args': {'event_uuid': 'w-1'},
      },
    );
    await store.enqueue(
      kind: 'withdraw',
      eventUuid: 'w-2',
      payload: {
        'args': {'event_uuid': 'w-2'},
      },
    );
    server.failNext['withdraw'] = Failure.auth;
    final r = await syncer.run();
    expect(r.stoppedBy, Failure.auth);
    expect(await store.count('pending'), 2);
  });

  test('a minor consent creates the guardian and one guardian link, then records with it', () async {
    await store.enqueue(
      kind: 'consent',
      eventUuid: 'u-4',
      principalRef: 'MHU-1',
      payload: consentPayload(
        'u-4',
        guardian: {
          'principal': {'principal_ref': 'MHU-1-G', 'full_name': 'Sunita D. (fictional)'},
          'link': {'guardian_type': 'parent', 'verification_method': 'device_sms_otp'},
        },
      ),
    );
    server.failNext['record'] = Failure.offline;
    await syncer.run();
    await syncer.run();
    expect(server.links.length, 1);
    expect(server.calls.where((c) => c == 'link').length, 1);
    expect(server.events['u-4']!['guardian_link'], 'GL-dp-MHU-1|dp-MHU-1-G');
  });

  test("a guardian's order photo and ID photo land in their own fields on the guardian link", () async {
    Future<Map<String, String>> photo(String name, String kind) async {
      final f = File('${tmp.path}/$name.jpg')..writeAsStringSync('photo $name (fictional)');
      final (id, sha) = await store.files!.adopt(f, 'jpg');
      return {'local': id, 'kind': kind, 'sha256': sha};
    }

    final order = await photo('order', 'guardian_order');
    final id = await photo('id', 'guardian_document');
    final payload = consentPayload(
      'u-6',
      guardian: {
        'principal': {'principal_ref': 'MHU-1-G', 'full_name': 'Suresh K. (fictional)'},
        'link': {'guardian_type': 'committee', 'authority_ref': 'LLC/2026/0412', 'verification_method': 'document'},
      },
    )..['guardian_evidence'] = [order, id];
    await store.enqueue(kind: 'consent', eventUuid: 'u-6', principalRef: 'MHU-1', payload: payload);
    await syncer.run();
    final link = server.links.values.single;
    expect(link['evidence'], '/private/files/u-6-guardian_order.jpg');
    expect(link['id_document'], '/private/files/u-6-guardian_document.jpg');
  });

  test('telling the coordinator syncs with the programme only', () async {
    await store.enqueue(kind: 'guardian_needed', programme: 'MHU', payload: {'programme': 'MHU'});
    final r = await syncer.run();
    expect(r.synced, 1);
    expect(server.told, ['MHU']);
  });

  test('local decisions: an older event never overrides a newer one', () async {
    await store.decide('MHU-1', 'MHU', 'follow', 'withdrawn', '2026-09-22 10:00:00', 'w');
    await store.decide('MHU-1', 'MHU', 'follow', 'granted', '2026-09-20 11:20:00', 'g');
    expect((await store.decisions('MHU-1', 'MHU'))['follow'], 'withdrawn');
  });

  test('offline search finds people by name, ID or receipt code', () async {
    await store.savePrincipal(LocalPrincipal(ref: 'MHU-9', programme: 'MHU', fullName: 'Radha S. (fictional)'));
    await store.enqueue(
      kind: 'consent',
      eventUuid: 'u-9',
      principalRef: 'MHU-9',
      shortCode: 'AN-ABC234',
      payload: consentPayload('u-9'),
    );
    expect((await store.search('radha')).single.ref, 'MHU-9');
    expect((await store.search('MHU-9')).single.ref, 'MHU-9');
    expect((await store.search('abc234')).single.ref, 'MHU-9');
    expect(await store.search('nobody'), isEmpty);
  });

  test('find by phone: their own number or their guardian\'s, so one family phone finds everyone', () async {
    await store.savePrincipal(
      LocalPrincipal(ref: 'MHU-20', programme: 'MHU', fullName: 'Radha S. (fictional)', phone: '5550001234'),
    );
    await store.saveServerPrincipal('MHU', {
      'principal_ref': 'MHU-21',
      'full_name': 'Meena S. (fictional)',
      'is_minor': 1,
      'guardian_phone': '555 000-1234',
      'guardian_relation': 'Mother',
      'decisions': [],
    });
    await store.savePrincipal(
      LocalPrincipal(ref: 'MHU-22', programme: 'MHU', fullName: 'Someone else (fictional)', phone: '5550009876'),
    );
    final family = await store.search('5550001234');
    expect(family.map((p) => p.ref).toSet(), {'MHU-20', 'MHU-21'});
    expect(family.firstWhere((p) => p.ref == 'MHU-20').phoneMatch('5550001234'), 'own');
    final child = family.firstWhere((p) => p.ref == 'MHU-21');
    expect(child.phoneMatch('5550001234'), 'guardian');
    expect(child.guardianRelation, 'Mother');
    expect((await store.search('+91 55500 01234')).map((p) => p.ref).toSet(), {'MHU-20', 'MHU-21'}, reason: '+91');
    expect((await store.search('1234')).map((p) => p.ref).toSet(), {'MHU-20', 'MHU-21'}, reason: 'last digits');
    expect(await store.search('123'), isEmpty, reason: 'fewer than 4 digits is not a phone search');
    expect((await store.search('radha')).single.ref, 'MHU-20', reason: 'name search unchanged');
  });

  test('messages go to the guardian for a child, to the person otherwise', () {
    final adult = LocalPrincipal(ref: 'A', programme: 'MHU', fullName: 'x', phone: '5550000001');
    expect(adult.contactPhone, '5550000001');
    final child = LocalPrincipal(
      ref: 'C',
      programme: 'MHU',
      fullName: 'x',
      flags: {'minor': true},
      guardianPhone: '5550000002',
    );
    expect(child.contactPhone, '5550000002');
    final noPhone = LocalPrincipal(ref: 'N', programme: 'MHU', fullName: 'x');
    expect(noPhone.contactPhone, isNull);
  });

  test('server errors map to park, retry later or sign in again', () {
    expect(SdkServer.classify(ValidationException('Unknown purpose')).kind, Failure.rejected);
    expect(SdkServer.classify(AuthException('expired', 401)).kind, Failure.auth);
    expect(SdkServer.classify(NetworkException('no route')).kind, Failure.offline);
    expect(SdkServer.classify(ApiException('boom', 502)).kind, Failure.offline);
    expect(SdkServer.classify(ApiException('missing', 404)).kind, Failure.rejected);
    expect(SdkServer.classify(Exception('weird')).kind, Failure.offline);
  });

  test('people from the server are stored for offline find, without overriding newer phone choices', () async {
    await store.decide('MHU-7', 'MHU', 'follow', 'withdrawn', '2026-09-25 10:00:00', 'local');
    await store.saveServerPrincipal('MHU', {
      'principal_ref': 'MHU-7',
      'full_name': 'Gauri P. (fictional)',
      'phone': '5550000007',
      'preferred_language': 'hi',
      'is_minor': 0,
      'last_code': 'AN-QWERTY',
      'decisions': [
        {'purpose': 'screen', 'status': 'granted', 'at': '2026-09-20 11:20:00'},
        {'purpose': 'follow', 'status': 'granted', 'at': '2026-09-20 11:20:00'},
      ],
    });
    expect((await store.search('gauri')).single.lastCode, 'AN-QWERTY');
    // A slip brought to a worker who did not take the consent still finds her by its code.
    expect((await store.search('qwerty')).single.ref, 'MHU-7');
    expect((await store.search('AN-QWERTY')).single.ref, 'MHU-7');
    final d = await store.decisions('MHU-7', 'MHU');
    expect(d['screen'], 'granted');
    expect(d['follow'], 'withdrawn', reason: 'the newer withdrawal on the phone wins');
  });
}
