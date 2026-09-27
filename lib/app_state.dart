import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:frappe_mobile_sdk/frappe_mobile_sdk.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'capture/draft.dart';
import 'core/strings.dart';
import 'data/server.dart';
import 'data/store.dart';
import 'data/sync.dart';

/// App-wide state: the SDK session, the encrypted store, the chosen
/// programme with its live notice, and the outbox counts shown on Home.
class AppState extends ChangeNotifier {
  static const _secure = FlutterSecureStorage();
  static const _baseUrlKey = 'anumati.base_url';

  FrappeSDK? sdk;
  Store? store;
  Server? server;
  Syncer? syncer;

  bool ready = false;
  bool signedIn = false;
  String userName = '';
  String deviceId = '';

  List<Map<String, dynamic>> programmes = [];
  String? programme;
  Map<String, dynamic>? programmeDoc;

  int pending = 0;
  int failed = 0;
  bool syncing = false;
  String? lastMessage;

  // ---------------------------------------------------------------- start-up

  Future<void> boot() async {
    store = await Store.open();
    deviceId = await store!.get('device_id') ?? const Uuid().v4();
    await store!.put('device_id', deviceId);
    Strings.uiLang = await store!.get('ui_lang') ?? 'en';
    final baseUrl = await _secure.read(key: _baseUrlKey);
    if (baseUrl != null) {
      try {
        await _attach(baseUrl, restore: true);
        signedIn = sdk!.isAuthenticated;
      } catch (_) {
        signedIn = false;
      }
    }
    if (signedIn) await _afterSignIn();
    ready = true;
    notifyListeners();
  }

  Future<void> _attach(String baseUrl, {bool restore = false}) async {
    await sdk?.dispose();
    sdk = FrappeSDK(baseUrl: baseUrl);
    await sdk!.initialize(restore);
    server = SdkServer(sdk!);
    final tmp = await getTemporaryDirectory();
    syncer = Syncer(store!, server!, tmp);
    Strings.server = (lang) => sdk?.translations.getCachedTranslations(lang) ?? const {};
  }

  static String normaliseUrl(String input) {
    var url = input.trim();
    if (!url.startsWith('http')) url = 'https://$url';
    if (!url.endsWith('/')) url = '$url/';
    return url;
  }

  /// Returns null on success, or a message to show.
  Future<String?> signIn(String address, String user, String password) async {
    final url = normaliseUrl(address);
    try {
      await _attach(url);
      await sdk!.login(user.trim(), password);
    } on AuthException {
      return tr('Could not sign in. Check your user ID and password.');
    } on NetworkException {
      return tr('Could not reach the server. Check the address and your internet.');
    } on ApiException catch (e) {
      if ((e.message).contains('mobile')) {
        return tr('This user is not allowed to use the field app. Ask your admin to add the Mobile User role.');
      }
      return tr('Could not sign in. Check your user ID and password.');
    } catch (_) {
      return tr('Could not reach the server. Check the address and your internet.');
    }
    await _secure.write(key: _baseUrlKey, value: url);
    signedIn = true;
    await _afterSignIn();
    notifyListeners();
    return null;
  }

  Future<void> _afterSignIn() async {
    userName = sdk?.currentUser?.fullName ?? sdk?.sessionUser?.fullName ?? '';
    programme = await store!.get('programme');
    programmes = List<Map<String, dynamic>>.from(await store!.getJson('programmes') as List? ?? const []);
    programmeDoc = programme == null ? null : await store!.getJson('programme:$programme') as Map<String, dynamic>?;
    await refreshCounts();
    unawaited(refreshReference());
  }

  /// Wipes the phone: SQLCipher database, evidence, keys, SDK session.
  Future<void> signOut() async {
    try {
      await sdk?.logout();
    } catch (_) {}
    await store?.wipe();
    await _secure.delete(key: _baseUrlKey);
    signedIn = false;
    programmes = [];
    programme = null;
    programmeDoc = null;
    store = await Store.open();
    await store!.put('device_id', deviceId);
    await refreshCounts();
    notifyListeners();
  }

  Future<void> setUiLang(String lang) async {
    Strings.uiLang = lang;
    await store!.put('ui_lang', lang);
    notifyListeners();
  }

  // ---------------------------------------------------------------- reference data

  Future<bool> online() async {
    final c = await Connectivity().checkConnectivity();
    return c.any((r) => r != ConnectivityResult.none);
  }

  /// Programmes, the chosen programme's settings and its notice in every
  /// language the programme uses, cached for offline capture.
  Future<void> refreshReference() async {
    if (server == null || !await online()) return;
    try {
      programmes = await server!.programmes();
      await store!.putJson('programmes', programmes);
      if (programme == null && programmes.length == 1) {
        programme = programmes.first['name'] as String;
        await store!.put('programme', programme);
      }
      if (programme != null) await _cacheProgramme(programme!);
    } on ServerFailure catch (f) {
      if (f.kind == Failure.auth) lastMessage = tr('Your session has ended. Sign in again to sync.');
    }
    notifyListeners();
  }

  Future<void> _cacheProgramme(String code) async {
    programmeDoc = await server!.programme(code);
    await store!.putJson('programme:$code', programmeDoc);
    for (final lang in Strings.languages.keys) {
      try {
        final n = await server!.activeNotice(code, lang);
        await store!.putJson('notice:$code:$lang', n);
        final audio = (n['translation'] as Map?)?['audio_file'] as String?;
        if (audio != null) {
          final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'audio'));
          await dir.create(recursive: true);
          final f = File(p.join(dir.path, '$code-$lang${p.extension(audio)}'));
          if (await server!.download(audio, f) != null) {
            await store!.put('audio:$code:$lang', f.path);
          }
        }
      } on ServerFailure catch (f) {
        if (f.kind != Failure.rejected) rethrow;
        await store!.put('notice:$code:$lang', null);
      }
    }
  }

  Future<void> selectProgramme(String code) async {
    programme = code;
    await store!.put('programme', code);
    programmeDoc = await store!.getJson('programme:$code') as Map<String, dynamic>?;
    notifyListeners();
    if (server != null && await online()) {
      try {
        await _cacheProgramme(code);
      } on ServerFailure catch (_) {}
      notifyListeners();
    }
  }

  String get programmeName {
    final row = programmes.where((r) => r['name'] == programme).firstOrNull;
    return (row?['programme_name'] ?? programme ?? '') as String;
  }

  Future<Notice?> notice(String lang) async {
    if (programme == null) return null;
    final raw = await store!.getJson('notice:$programme:$lang') ?? await store!.getJson('notice:$programme:en');
    return raw == null ? null : Notice(Map<String, dynamic>.from(raw as Map));
  }

  Future<String?> audioPath(String lang) async {
    final path = await store!.get('audio:$programme:$lang');
    return (path != null && await File(path).exists()) ? path : null;
  }

  /// Verification methods this programme allows that work from the phone.
  List<String> get allowedVerification {
    const onPhone = ['device_sms_otp', 'deferred', 'evidence_only'];
    final rows = (programmeDoc?['verification_methods'] as List?) ?? const [];
    final allowed = [for (final r in rows) (r as Map)['verification_method'] as String];
    return allowed.isEmpty ? onPhone : onPhone.where(allowed.contains).toList();
  }

  // ---------------------------------------------------------------- capture

  Future<void> saveConsent(CaptureDraft d) async {
    final now = DateTime.now();
    await store!.savePrincipal(d.toLocal());
    await store!.enqueue(
      kind: 'consent',
      payload: d.toPayload(now),
      eventUuid: d.eventUuid,
      principalRef: d.principalRef,
      programme: d.programme,
      shortCode: d.shortCode,
    );
    final at = CaptureDraft.deviceTime(now);
    for (final c in d.granted) {
      await store!.decide(d.principalRef, d.programme, c, 'granted', at, d.eventUuid);
    }
    for (final c in d.denied) {
      await store!.decide(d.principalRef, d.programme, c, 'refused', at, d.eventUuid);
    }
    await _afterWrite();
  }

  Future<void> saveWithdrawal({required String principalRef, required String channel, List<String>? purposes}) async {
    final eventUuid = const Uuid().v4();
    final now = DateTime.now();
    final at = CaptureDraft.deviceTime(now);
    await store!.enqueue(
      kind: 'withdraw',
      eventUuid: eventUuid,
      principalRef: principalRef,
      programme: programme,
      payload: {
        'args': {
          'principal_ref': principalRef,
          'programme': programme,
          'channel': channel,
          'event_uuid': eventUuid,
          'purposes': ?purposes,
          'device_id': deviceId,
          'device_time': at,
        },
      },
    );
    final notice = await this.notice('en');
    final decided = await store!.decisions(principalRef, programme!);
    final targets =
        purposes ??
        [
          for (final p in notice?.purposes ?? const <NoticePurpose>[])
            if (!p.essential && decided[p.code] == 'granted') p.code,
        ];
    for (final c in targets) {
      await store!.decide(principalRef, programme!, c, 'withdrawn', at, eventUuid);
    }
    await _afterWrite();
  }

  Future<void> saveRequest({
    required String requestType,
    required String channel,
    String? principalRef,
    String? note,
    String? paperTrail,
  }) async {
    await store!.enqueue(
      kind: 'request',
      principalRef: principalRef,
      programme: programme,
      payload: {
        'args': {
          'request_type': requestType,
          'channel': channel,
          'principal_ref': ?principalRef,
          if (note != null && note.isNotEmpty) 'payload': note,
          if (paperTrail != null && paperTrail.isNotEmpty) 'paper_trail_number': paperTrail,
        },
      },
    );
    await _afterWrite();
  }

  /// Just-in-time consent for purposes added to the notice later.
  Future<String> saveAddedPurposes({
    required LocalPrincipal principal,
    required Notice notice,
    required Map<String, bool> answers,
    required String verifyMethod,
    required bool confirmed,
  }) async {
    final d = CaptureDraft(programme: programme!, deviceId: deviceId)
      ..principalRef = principal.ref
      ..lang = principal.lang
      ..notice = notice
      ..verifyMethod = verifyMethod
      ..otpConfirmed = confirmed
      ..selfChosen = true;
    d.flags.addAll(principal.flags);
    final now = DateTime.now();
    final at = CaptureDraft.deviceTime(now);
    final granted = [
      for (final e in answers.entries)
        if (e.value) e.key,
    ];
    final denied = [
      for (final e in answers.entries)
        if (!e.value) e.key,
    ];
    await store!.enqueue(
      kind: 'consent',
      eventUuid: d.eventUuid,
      principalRef: principal.ref,
      programme: programme,
      shortCode: d.shortCode,
      payload: {
        'principal': {'principal_ref': principal.ref},
        'evidence': [],
        'event': {
          'event_uuid': d.eventUuid,
          'principal_ref': principal.ref,
          'programme': programme,
          'action': 'grant',
          'purposes_granted': granted,
          'purposes_denied': denied,
          'notice': notice.name,
          'language': principal.lang,
          'capture_mode': 'self_worker_device',
          'channel': 'app',
          'device_id': deviceId,
          'device_time': at,
          'verification_method': verifyMethod,
          'verification_status': d.verificationStatus,
        },
      },
    );
    for (final c in granted) {
      await store!.decide(principal.ref, programme!, c, 'granted', at, d.eventUuid);
    }
    for (final c in denied) {
      await store!.decide(principal.ref, programme!, c, 'refused', at, d.eventUuid);
    }
    await store!.savePrincipal(principal.copyWith(lastCode: d.shortCode));
    await _afterWrite();
    return d.shortCode;
  }

  Future<void> _afterWrite() async {
    await refreshCounts();
    notifyListeners();
    unawaited(sync(quiet: true));
  }

  // ---------------------------------------------------------------- sync

  Future<void> refreshCounts() async {
    pending = await store!.count('pending');
    failed = await store!.count('failed');
  }

  Future<void> countsChanged() async {
    await refreshCounts();
    notifyListeners();
  }

  Future<void> sync({bool quiet = false}) async {
    if (syncer == null || syncing) return;
    if (!await online()) {
      if (!quiet) lastMessage = tr('No internet. Records stay safe on this phone.');
      notifyListeners();
      return;
    }
    syncing = true;
    notifyListeners();
    try {
      final r = await syncer!.run();
      if (r.stoppedBy == Failure.auth) {
        lastMessage = tr('Your session has ended. Sign in again to sync.');
        signedIn = false;
      } else if (r.stoppedBy == Failure.offline) {
        if (!quiet) lastMessage = tr('No internet. Records stay safe on this phone.');
      } else if (!quiet) {
        lastMessage = tr('Sync finished');
      }
      if (r.synced > 0) unawaited(refreshReference());
    } finally {
      syncing = false;
      await refreshCounts();
      notifyListeners();
    }
  }

  String? takeMessage() {
    final m = lastMessage;
    lastMessage = null;
    return m;
  }
}
