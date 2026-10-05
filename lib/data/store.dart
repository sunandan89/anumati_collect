import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' as hash;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Everything this phone keeps: an SQLCipher database (names, phones, the
/// outbox) and AES-GCM encrypted evidence files. Both keys live in the
/// Android Keystore via flutter_secure_storage and never leave the phone.
class Store {
  Store(this.db, {this.files});

  final Database db;
  final EvidenceFiles? files;

  static const _dbName = 'anumati_collect.db';
  static const _dbKey = 'anumati.db_key';
  static const _fileKey = 'anumati.file_key';
  static const _storage = FlutterSecureStorage();

  static Future<Store> open() async {
    final dbKey = await _key(_dbKey);
    final fileKey = await _key(_fileKey);
    final dir = await getApplicationDocumentsDirectory();
    final db = await openDatabase(
      p.join(dir.path, _dbName),
      password: dbKey,
      version: 3,
      onCreate: (db, _) => createSchema(db),
      onUpgrade: (db, from, to) async {
        if (from < 2) await db.execute("ALTER TABLE principals ADD COLUMN source TEXT DEFAULT 'phone'");
        if (from < 3) {
          await db.execute('ALTER TABLE principals ADD COLUMN guardian_phone TEXT');
          await db.execute('ALTER TABLE principals ADD COLUMN guardian_relation TEXT');
        }
      },
    );
    final evDir = Directory(p.join(dir.path, 'evidence'));
    await evDir.create(recursive: true);
    return Store(db, files: EvidenceFiles(evDir, base64Decode(fileKey)));
  }

  static Future<String> _key(String name) async {
    final existing = await _storage.read(key: name);
    if (existing != null) return existing;
    final r = Random.secure();
    final key = base64Encode(List.generate(32, (_) => r.nextInt(256)));
    await _storage.write(key: name, value: key);
    return key;
  }

  /// Sign-out wipe: database, evidence and both keys.
  Future<void> wipe() async {
    final path = db.path;
    await db.close();
    await deleteDatabase(path);
    await files?.wipe();
    await _storage.delete(key: _dbKey);
    await _storage.delete(key: _fileKey);
  }

  static Future<void> createSchema(Database db) async {
    await db.execute('CREATE TABLE kv (key TEXT PRIMARY KEY, value TEXT)');
    await db.execute('''CREATE TABLE principals (
      ref TEXT PRIMARY KEY, programme TEXT, full_name TEXT, phone TEXT, lang TEXT,
      flags TEXT, last_code TEXT, verification_method TEXT, created_at TEXT, source TEXT DEFAULT 'phone',
      guardian_phone TEXT, guardian_relation TEXT)''');
    await db.execute('''CREATE TABLE outbox (
      id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT NOT NULL, event_uuid TEXT UNIQUE,
      principal_ref TEXT, programme TEXT, payload TEXT NOT NULL, progress TEXT,
      status TEXT NOT NULL DEFAULT 'pending', attempts INTEGER NOT NULL DEFAULT 0,
      error TEXT, short_code TEXT, created_at TEXT, synced_at TEXT)''');
    await db.execute('''CREATE TABLE decisions (
      principal_ref TEXT, programme TEXT, purpose TEXT, status TEXT, at TEXT, event_uuid TEXT,
      PRIMARY KEY (principal_ref, programme, purpose))''');
  }

  // ------------------------------------------------------------------ kv

  Future<String?> get(String key) async {
    final rows = await db.query('kv', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> put(String key, String? value) =>
      db.insert('kv', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<dynamic> getJson(String key) async {
    final v = await get(key);
    return v == null ? null : jsonDecode(v);
  }

  Future<void> putJson(String key, Object? value) => put(key, jsonEncode(value));

  // ------------------------------------------------------------------ principals

  Future<void> savePrincipal(LocalPrincipal pr) =>
      db.insert('principals', pr.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);

  /// A person downloaded from the server (principal.for_device). People captured on this phone and not
  /// yet synced keep their local copy; server choices never override a newer local decision.
  Future<void> saveServerPrincipal(String programme, Map<String, dynamic> p) async {
    final ref = p['principal_ref'] as String;
    final existing = await principal(ref);
    bool b(String k) => p[k] == 1 || p[k] == true;
    await db.insert('principals', {
      'ref': ref,
      'programme': programme,
      'full_name': (p['full_name'] as String?)?.isNotEmpty == true ? p['full_name'] : existing?.fullName ?? '',
      'phone': (p['phone'] as String?)?.isNotEmpty == true ? p['phone'] : existing?.phone,
      'lang': p['preferred_language'] ?? existing?.lang ?? 'en',
      'flags': jsonEncode({
        'minor': b('is_minor'),
        'pwd': b('pwd_guarded'),
        'read': b('needs_assistance'),
        'shared': b('shared_phone'),
        'nophone': b('no_phone'),
      }),
      'last_code': p['last_code'] ?? existing?.lastCode,
      'guardian_phone': (p['guardian_phone'] as String?)?.isNotEmpty == true
          ? p['guardian_phone']
          : existing?.guardianPhone,
      'guardian_relation': (p['guardian_relation'] as String?)?.isNotEmpty == true
          ? p['guardian_relation']
          : existing?.guardianRelation,
      'verification_method': existing?.verificationMethod,
      'created_at': existing?.createdAt ?? DateTime.now().toIso8601String(),
      'source': existing == null ? 'server' : 'phone',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    for (final d in (p['decisions'] as List? ?? const [])) {
      final m = d as Map;
      await decide(ref, programme, m['purpose'] as String, m['status'] as String, '${m['at'] ?? ''}', 'server');
    }
  }

  Future<LocalPrincipal?> principal(String ref) async {
    final rows = await db.query('principals', where: 'ref = ?', whereArgs: [ref]);
    return rows.isEmpty ? null : LocalPrincipal.fromRow(rows.first);
  }

  /// A stored phone number without the separators people type: spaces, dashes, brackets, dots.
  static String _digitsOnly(String col) {
    var e = col;
    for (final c in [' ', '-', '(', ')', '.']) {
      e = "REPLACE($e, '$c', '')";
    }
    return e;
  }

  /// Offline search over people on this phone (captured here or downloaded): name, ID, receipt code, or
  /// phone number (their own or their guardian's, so one family phone finds the parent and the children).
  Future<List<LocalPrincipal>> search(String q, {String? programme}) async {
    final like = '%${q.trim()}%';
    final code = q.trim().toUpperCase();
    final digits = phoneDigits(q);
    // At least 4 digits, and nothing but a phone number was typed (spaces, + or - allowed).
    final byPhone = digits.length >= 4 && RegExp(r'^[\d\s+\-().]+$').hasMatch(q.trim()) ? '%$digits%' : null;
    final rows = await db.rawQuery(
      '''SELECT DISTINCT p.* FROM principals p
         LEFT JOIN outbox o ON o.principal_ref = p.ref
         WHERE (? IS NULL OR p.programme = ?)
           AND (p.full_name LIKE ? OR p.ref LIKE ? OR o.short_code IN (?, ?) OR p.last_code IN (?, ?)
                OR (? IS NOT NULL AND (${_digitsOnly('p.phone')} LIKE ? OR ${_digitsOnly('p.guardian_phone')} LIKE ?)))
         ORDER BY p.created_at DESC LIMIT 50''',
      [programme, programme, like, like, code, 'AN-$code', code, 'AN-$code', byPhone, byPhone, byPhone],
    );
    return rows.map(LocalPrincipal.fromRow).toList();
  }

  // ------------------------------------------------------------------ outbox

  Future<int> enqueue({
    required String kind,
    required Map<String, dynamic> payload,
    String? eventUuid,
    String? principalRef,
    String? programme,
    String? shortCode,
  }) => db.insert('outbox', {
    'kind': kind,
    'event_uuid': eventUuid,
    'principal_ref': principalRef,
    'programme': programme,
    'payload': jsonEncode(payload),
    'short_code': shortCode,
    'created_at': DateTime.now().toIso8601String(),
  });

  Future<List<OutboxItem>> pending() async {
    final rows = await db.query('outbox', where: "status = 'pending'", orderBy: 'id');
    return rows.map(OutboxItem.fromRow).toList();
  }

  Future<List<OutboxItem>> failed() async {
    final rows = await db.query('outbox', where: "status = 'failed'", orderBy: 'id');
    return rows.map(OutboxItem.fromRow).toList();
  }

  Future<int> count(String status) async {
    final r = await db.rawQuery('SELECT COUNT(*) AS n FROM outbox WHERE status = ?', [status]);
    return (r.first['n'] as int?) ?? 0;
  }

  Future<void> saveProgress(int id, Map<String, dynamic> progress) =>
      db.update('outbox', {'progress': jsonEncode(progress)}, where: 'id = ?', whereArgs: [id]);

  Future<void> markSynced(int id, {String? shortCode}) => db.update(
    'outbox',
    {'status': 'synced', 'error': null, 'synced_at': DateTime.now().toIso8601String(), 'short_code': ?shortCode},
    where: 'id = ?',
    whereArgs: [id],
  );

  /// pending, synced or failed; null if this phone has no such record.
  Future<String?> statusOf(String eventUuid) async {
    final rows = await db.query('outbox', columns: ['status'], where: 'event_uuid = ?', whereArgs: [eventUuid]);
    return rows.isEmpty ? null : rows.first['status'] as String?;
  }

  Future<void> markFailed(int id, String error) =>
      db.rawUpdate("UPDATE outbox SET status = 'failed', error = ?, attempts = attempts + 1 WHERE id = ?", [error, id]);

  Future<void> retry(int id) =>
      db.update('outbox', {'status': 'pending', 'error': null}, where: 'id = ?', whereArgs: [id]);

  Future<void> discard(int id) => db.delete('outbox', where: "id = ? AND status != 'synced'", whereArgs: [id]);

  // ------------------------------------------------------------------ decisions

  /// Apply a decision locally at once (spec B4: a withdrawal takes effect on
  /// the phone immediately). Older events never override newer ones.
  Future<void> decide(String ref, String programme, String purpose, String status, String at, String eventUuid) async {
    final rows = await db.query(
      'decisions',
      where: 'principal_ref = ? AND programme = ? AND purpose = ?',
      whereArgs: [ref, programme, purpose],
    );
    if (rows.isNotEmpty && (rows.first['at'] as String).compareTo(at) > 0) {
      return;
    }
    await db.insert('decisions', {
      'principal_ref': ref,
      'programme': programme,
      'purpose': purpose,
      'status': status,
      'at': at,
      'event_uuid': eventUuid,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, String>> decisions(String ref, String programme) async {
    final rows = await db.query('decisions', where: 'principal_ref = ? AND programme = ?', whereArgs: [ref, programme]);
    return {for (final r in rows) r['purpose'] as String: r['status'] as String};
  }

  /// Evidence ids still referenced by an unsynced record.
  Future<Set<String>> referencedEvidence() async {
    final rows = await db.query('outbox', columns: ['payload'], where: "status != 'synced'");
    final ids = <String>{};
    for (final r in rows) {
      final payload = jsonDecode(r['payload'] as String) as Map<String, dynamic>;
      for (final key in ['evidence', 'guardian_evidence']) {
        for (final e in (payload[key] as List? ?? const [])) {
          ids.add((e as Map)['local'] as String);
        }
      }
    }
    return ids;
  }
}

/// The digits of a phone number as typed, without a country code or leading 0: an Indian mobile number is
/// its last 10 digits ("+91 98765-43210" and "098765 43210" -> "9876543210"). A country code typed before
/// part of a number is dropped too ("+91 98765" -> "98765").
String phoneDigits(String s) {
  final t = s.trim();
  var d = t.replaceAll(RegExp(r'\D'), '');
  if (d.length > 10) return d.substring(d.length - 10);
  if (t.startsWith('+91') && d.startsWith('91')) {
    d = d.substring(2);
  } else if (t.startsWith('0')) {
    d = d.replaceFirst(RegExp('^0+'), '');
  }
  return d;
}

class LocalPrincipal {
  LocalPrincipal({
    required this.ref,
    required this.programme,
    required this.fullName,
    this.phone,
    this.lang = 'en',
    this.flags = const {},
    this.lastCode,
    this.verificationMethod,
    this.guardianPhone,
    this.guardianRelation,
    String? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toIso8601String();

  final String ref;
  final String programme;
  final String fullName;
  final String? phone;
  final String lang;
  final Map<String, bool> flags;
  final String? lastCode;
  final String? verificationMethod;

  /// The latest parent's or guardian's number and relation (Mother, Father, …), for finding by phone.
  final String? guardianPhone;
  final String? guardianRelation;
  final String createdAt;

  bool flag(String k) => flags[k] ?? false;

  /// The number messages about them go to: for a child or an adult with a guardian, the guardian's (the
  /// guardian decided); otherwise their own, or the guardian's if they have none. Same rule as the server.
  String? get contactPhone {
    final own = (phone ?? '').isEmpty ? null : phone;
    final guardian = (guardianPhone ?? '').isEmpty ? null : guardianPhone;
    return (flag('minor') || flag('pwd')) ? (guardian ?? own) : (own ?? guardian);
  }

  /// How a typed phone number matched: 'own', 'guardian', or null (not a phone search, or no match).
  String? phoneMatch(String query) {
    final d = phoneDigits(query);
    if (d.length < 4) return null;
    if (phoneDigits(phone ?? '').contains(d)) return 'own';
    if (phoneDigits(guardianPhone ?? '').contains(d)) return 'guardian';
    return null;
  }

  Map<String, Object?> toRow() => {
    'ref': ref,
    'programme': programme,
    'full_name': fullName,
    'phone': phone,
    'lang': lang,
    'flags': jsonEncode(flags),
    'last_code': lastCode,
    'verification_method': verificationMethod,
    'guardian_phone': guardianPhone,
    'guardian_relation': guardianRelation,
    'created_at': createdAt,
  };

  static LocalPrincipal fromRow(Map<String, Object?> r) => LocalPrincipal(
    ref: r['ref'] as String,
    programme: r['programme'] as String? ?? '',
    fullName: r['full_name'] as String? ?? '',
    phone: r['phone'] as String?,
    lang: r['lang'] as String? ?? 'en',
    flags: Map<String, bool>.from(jsonDecode(r['flags'] as String? ?? '{}') as Map),
    lastCode: r['last_code'] as String?,
    verificationMethod: r['verification_method'] as String?,
    guardianPhone: r['guardian_phone'] as String?,
    guardianRelation: r['guardian_relation'] as String?,
    createdAt: r['created_at'] as String?,
  );

  LocalPrincipal copyWith({String? lastCode, String? verificationMethod}) => LocalPrincipal(
    ref: ref,
    programme: programme,
    fullName: fullName,
    phone: phone,
    lang: lang,
    flags: flags,
    lastCode: lastCode ?? this.lastCode,
    verificationMethod: verificationMethod ?? this.verificationMethod,
    guardianPhone: guardianPhone,
    guardianRelation: guardianRelation,
    createdAt: createdAt,
  );
}

class OutboxItem {
  OutboxItem(this.row);
  final Map<String, Object?> row;

  int get id => row['id'] as int;
  String get kind => row['kind'] as String;
  String? get eventUuid => row['event_uuid'] as String?;
  String? get principalRef => row['principal_ref'] as String?;
  String? get programme => row['programme'] as String?;
  String? get shortCode => row['short_code'] as String?;
  String? get error => row['error'] as String?;
  String get createdAt => row['created_at'] as String? ?? '';
  Map<String, dynamic> get payload => jsonDecode(row['payload'] as String) as Map<String, dynamic>;
  Map<String, dynamic> get progress =>
      row['progress'] == null ? <String, dynamic>{} : jsonDecode(row['progress'] as String) as Map<String, dynamic>;

  static OutboxItem fromRow(Map<String, Object?> r) => OutboxItem(r);
}

/// Evidence (voice clips, thumbprint and document photos) encrypted at rest
/// with AES-256-GCM. Files are removed once the record has synced.
class EvidenceFiles {
  EvidenceFiles(this.dir, List<int> key) : _key = SecretKey(key);

  final Directory dir;
  final SecretKey _key;
  final _aes = AesGcm.with256bits();

  /// Encrypt [plain] into the store, delete the plaintext, return (id, sha256).
  Future<(String, String)> adopt(File plain, String ext) async {
    final bytes = await plain.readAsBytes();
    final sha = hash.sha256.convert(bytes).toString();
    final box = await _aes.encrypt(bytes, secretKey: _key);
    final id = '${DateTime.now().microsecondsSinceEpoch}.$ext';
    await File(p.join(dir.path, id)).writeAsBytes(box.concatenation());
    await plain.delete();
    return (id, sha);
  }

  /// Decrypt to a temporary file for upload. The caller deletes it.
  Future<File> reveal(String id, Directory tmp) async {
    final data = await File(p.join(dir.path, id)).readAsBytes();
    final box = SecretBox.fromConcatenation(
      data,
      nonceLength: _aes.nonceLength,
      macLength: _aes.macAlgorithm.macLength,
    );
    final plain = await _aes.decrypt(box, secretKey: _key);
    final out = File(p.join(tmp.path, id));
    await out.writeAsBytes(plain, flush: true);
    return out;
  }

  Future<void> remove(String id) async {
    final f = File(p.join(dir.path, id));
    if (await f.exists()) await f.delete();
  }

  Future<void> wipe() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
