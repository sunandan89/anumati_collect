import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:frappe_mobile_sdk/frappe_mobile_sdk.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'capture/draft.dart';
import 'core/strings.dart';
import 'core/version.dart';
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

  // App lock: a 4-digit PIN, asked on start and after 5 minutes away (the phone holds names and evidence).
  static const _pinKey = 'anumati.pin';
  static const lockAfter = Duration(minutes: 5);
  static const maxPinTries = 5;
  bool hasPin = false;
  bool locked = false;
  int pinTries = 0;
  DateTime? _pausedAt;
  String userName = '';
  String deviceId = '';

  List<Map<String, dynamic>> programmes = [];
  String? programme;
  Map<String, dynamic>? programmeDoc;

  /// From Mobile Control's app status (checked in the background, never blocking start-up).
  String? blockedReason;
  bool updateRequired = false;

  /// The server offers the spoken yes/no hint (Sarvam); set at check-in, off by default.
  bool voiceHelper = false;

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
    hasPin = (await _secure.read(key: _pinKey)) != null;
    locked = signedIn && hasPin;
    if (signedIn) await _afterSignIn();
    ready = true;
    notifyListeners();
  }

  Future<void> _attach(String baseUrl, {bool restore = false}) async {
    await sdk?.dispose();
    sdk = FrappeSDK(baseUrl: baseUrl);
    // Start fast: restore the saved session from the phone only. The SDK's own start-up sync (meta,
    // permissions, translations over the network) is skipped; the app syncs in the background once
    // Home is on screen, and an expired token is refreshed on the first 401.
    await sdk!.initialize(false);
    if (restore) await sdk!.auth.restoreSession(isOnline: false);
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

  /// Returns null on success, or a message to show. Checks in order so the
  /// message says what is actually wrong: can the phone reach the site, is
  /// Frappe Mobile Control installed and switched on, then the login itself.
  Future<String?> signIn(String address, String user, String password) async {
    final url = normaliseUrl(address);
    try {
      await _attach(url);
    } catch (e) {
      return tr('Could not start the app: {0}', [_short(e)]);
    }
    try {
      await sdk!.api.rest.callPublic('ping', httpMethod: 'GET');
    } catch (e) {
      return '${tr('Could not reach the server. Check the address and your internet.')}\n(${_short(e)})';
    }
    try {
      final status = await sdk!.api.rest.callPublic('mobile_auth.app_status', httpMethod: 'GET');
      final msg = status is Map ? (status['message'] ?? status) : status;
      if (msg is Map && msg['enabled'] == false) {
        return tr('The field app is switched off on this site. In Desk, open Mobile Configuration and tick Enabled.');
      }
    } catch (e) {
      if (e is FrappeException && (e.statusCode == 404 || e.statusCode == 417 || e.statusCode == 403)) {
        return tr('Frappe Mobile Control is not installed on this site. Ask your admin to install it.');
      }
    }
    try {
      await sdk!.login(user.trim(), password);
    } on AuthException {
      return tr('Could not sign in. Check your user ID and password.');
    } on NetworkException catch (e) {
      return '${tr('Could not reach the server. Check the address and your internet.')}\n(${_short(e)})';
    } on FrappeException catch (e) {
      final m = e.message.toLowerCase();
      if (m.contains('not allowed to use mobile')) {
        return tr('This user is not allowed to use the field app. Ask your admin to add the Mobile User role.');
      }
      if (m.contains('unable to login') || m.contains('invalid login') || m.contains('incorrect')) {
        return tr('Could not sign in. Check your user ID and password.');
      }
      return tr('The server refused the sign-in: {0}', [e.message]);
    } catch (e) {
      return tr('Sign-in failed: {0}', [_short(e)]);
    }
    await _secure.write(key: _baseUrlKey, value: url);
    signedIn = true;
    await _afterSignIn();
    notifyListeners();
    return null;
  }

  static String _short(Object e) {
    final s = e.toString().replaceAll(RegExp(r'\s+'), ' ');
    return s.length > 160 ? '${s.substring(0, 160)}…' : s;
  }

  Future<void> _afterSignIn() async {
    userName = sdk?.currentUser?.fullName ?? sdk?.sessionUser?.fullName ?? '';
    programme = await store!.get('programme');
    programmes = List<Map<String, dynamic>>.from(await store!.getJson('programmes') as List? ?? const []);
    programmeDoc = programme == null ? null : await store!.getJson('programme:$programme') as Map<String, dynamic>?;
    await refreshCounts();
    unawaited(checkAppStatus());
    unawaited(refreshReference().then((_) => sync(quiet: true)));
  }

  /// Wipes the phone: SQLCipher database, evidence, keys, SDK session.
  Future<void> signOut() async {
    try {
      await sdk?.logout();
    } catch (_) {}
    await store?.wipe();
    await _secure.delete(key: _baseUrlKey);
    await _secure.delete(key: _pinKey);
    hasPin = false;
    locked = false;
    pinTries = 0;
    signedIn = false;
    programmes = [];
    programme = null;
    programmeDoc = null;
    store = await Store.open();
    await store!.put('device_id', deviceId);
    await refreshCounts();
    notifyListeners();
  }

  static String _pinHash(String salt, String pin) => sha256.convert(utf8.encode('$salt:$pin')).toString();

  Future<void> setPin(String pin) async {
    final salt = const Uuid().v4();
    await _secure.write(key: _pinKey, value: '$salt:${_pinHash(salt, pin)}');
    hasPin = true;
    locked = false;
    pinTries = 0;
    notifyListeners();
  }

  /// Returns true when the PIN is right. After [maxPinTries] wrong tries the phone signs out and wipes.
  Future<bool> unlock(String pin) async {
    final stored = await _secure.read(key: _pinKey);
    final parts = stored?.split(':');
    if (parts != null && parts.length == 2 && _pinHash(parts[0], pin) == parts[1]) {
      locked = false;
      pinTries = 0;
      notifyListeners();
      return true;
    }
    pinTries++;
    if (pinTries >= maxPinTries) {
      await signOut();
      lastMessage = tr('Too many wrong PINs. This phone was signed out and its data deleted.');
    }
    notifyListeners();
    return false;
  }

  void appPaused() => _pausedAt = DateTime.now();

  void appResumed() {
    if (signedIn) unawaited(checkAppStatus());
    final at = _pausedAt;
    _pausedAt = null;
    if (signedIn && hasPin && at != null && DateTime.now().difference(at) >= lockAfter) {
      locked = true;
      notifyListeners();
    }
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
        final card = ((n['translation'] as Map?)?['pictorial_card'] ?? n['pictorial_card']) as String?;
        if (card != null) {
          final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'cards'));
          await dir.create(recursive: true);
          final f = File(p.join(dir.path, '$code-$lang${p.extension(card)}'));
          if (await server!.download(card, f) != null) await store!.put('card:$code:$lang', f.path);
        }
        // Approved recording in her language, else the approved base-notice recording when the
        // base text is what she will hear.
        final tr = n['translation'] as Map?;
        final src = tr ?? n;
        // Both approved recordings (woman's and man's voice), so either plays offline.
        await store!.put('audio_ai:$code:$lang', Notice(n).audioByAi ? '1' : null);
        for (final (field, key) in [('audio_file', 'audio'), ('audio_file_male', 'audio_m')]) {
          final audio = src[field] as String?;
          if (audio == null) continue;
          final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'audio'));
          await dir.create(recursive: true);
          final f = File(p.join(dir.path, '$code-$lang-$key${p.extension(audio)}'));
          if (await server!.download(audio, f) != null) {
            await store!.put('$key:$code:$lang', f.path);
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
      await pullPeople();
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

  Future<String?> cardPath(String lang) async {
    final path = await store!.get('card:$programme:$lang');
    return (path != null && await File(path).exists()) ? path : null;
  }

  /// The approved recording to play: the voice matching this worker first, else the other one.
  Future<String?> audioPath(String lang) async {
    final male = await store!.get('voice') == 'male';
    for (final key in male ? ['audio_m', 'audio'] : ['audio', 'audio_m']) {
      final path = await store!.get('$key:$programme:$lang');
      if (path != null && await File(path).exists()) return path;
    }
    return null;
  }

  /// Whether the recording was made with Sarvam AI's voice, so the notice screen can credit it.
  Future<bool> audioByAi(String lang) async => await store!.get('audio_ai:$programme:$lang') == '1';

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

  /// An adult who can't decide alone has no appointed guardian: tell the coordinator (no personal data)
  /// through the outbox, so it also works offline. Nothing about the person is stored.
  Future<void> informCoordinator() async {
    await store!.enqueue(kind: 'guardian_needed', programme: programme, payload: {'programme': programme});
    await _afterWrite();
  }

  /// Just-in-time consent for purposes added to the notice later.
  Future<String> saveAddedPurposes({
    required LocalPrincipal principal,
    required Notice notice,
    required Map<String, bool> answers,
    required String verifyMethod,
    required bool confirmed,
    String? witness,
  }) async {
    final d = CaptureDraft(programme: programme!, deviceId: deviceId)
      ..principalRef = principal.ref
      ..lang = principal.lang
      ..notice = notice
      ..verifyMethod = verifyMethod
      ..otpConfirmed = confirmed;
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
          'capture_mode': principal.flag('read') ? 'assisted_witnessed' : 'self_worker_device',
          'channel': 'app',
          'device_id': deviceId,
          'device_time': at,
          'verification_method': verifyMethod,
          'verification_status': d.verificationStatus,
          if (notice.supportsDelivery) ...{'notice_delivery': 'read_aloud', 'notice_completed': 1},
          if (witness != null && witness.isNotEmpty) 'witness': witness,
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
      if (await _checkIn()) return;
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
      if (r.stoppedBy == null) await pullPeople();
    } finally {
      syncing = false;
      await refreshCounts();
      notifyListeners();
    }
  }

  static bool _older(String mine, String min) {
    List<int> parts(String v) => v.split(RegExp(r'[.+-]')).map((x) => int.tryParse(x) ?? 0).toList();
    final a = parts(mine), b = parts(min);
    for (var i = 0; i < 3; i++) {
      final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
      if (x != y) return x < y;
    }
    return false;
  }

  /// Mobile Control's switch-off, maintenance and minimum-version check, done in the background with a
  /// short timeout (the SDK's guard waits up to ~90 s on a weak network before showing anything).
  /// The last answer is remembered, so a switched-off or outdated app stays blocked offline too.
  Future<void> checkAppStatus() async {
    final base = sdk;
    if (base == null) return;
    Map? status;
    try {
      final out = await base.api.rest.getPublic(
        '/api/v2/method/mobile_auth.app_status',
        timeout: const Duration(seconds: 8),
        maxRetries: 0,
      );
      final m = out is Map ? (out['data'] ?? out['message'] ?? out) : null;
      if (m is Map) {
        status = m;
        await store!.putJson('app_status', m);
      }
    } catch (_) {
      status = await store!.getJson('app_status') as Map?;
    }
    if (status == null) return;
    final enabled = status['enabled'] != false;
    final maintenance = status['maintenance_mode'] == true;
    final min = (status['version'] as String?) ?? '';
    blockedReason = !enabled
        ? tr('The field app is switched off on this site. In Desk, open Mobile Configuration and tick Enabled.')
        : maintenance
        ? ((status['maintenance_message'] as String?)?.isNotEmpty == true
              ? status['maintenance_message'] as String
              : tr('The server is under maintenance. Your records stay safe on this phone.'))
        : null;
    updateRequired = enabled && min.isNotEmpty && _older(appVersion, min);
    notifyListeners();
  }

  /// A hint for the worker: what Sarvam heard in the clip and whether it sounds like yes or no.
  /// Null when the helper is off, the phone is offline or anything fails; capture never waits on it.
  Future<Map<String, dynamic>?> hearClip(List<int> clip, String? language) async {
    if (!voiceHelper || server == null || !await online()) return null;
    try {
      return await server!.hear(clip, language).timeout(const Duration(seconds: 20));
    } catch (_) {
      return null;
    }
  }

  /// Device check-in (Field Device). Returns true if the phone was reported lost and has been wiped.
  Future<bool> _checkIn() async {
    try {
      final out = await server!.registerDevice(
        deviceId,
        appVersion: appVersion,
        model: Platform.operatingSystemVersion,
        pending: pending + failed,
      );
      voiceHelper = out?['voice_helper'] == true;
      // Woman's or man's recording of the notice, matching this worker (kept for offline starts).
      if (out?['voice'] is String) await store!.put('voice', out!['voice'] as String);
      if (out != null && out['wipe'] == true) {
        await signOut();
        lastMessage = tr('This phone was reported lost. Its data has been deleted. Sign in again to use it.');
        return true;
      }
    } on ServerFailure catch (_) {
      // Older servers have no device check-in; a network or login problem shows up in the sync itself.
    }
    return false;
  }

  /// Download the programme's people and their choices into the encrypted store (offline find,
  /// withdrawal and add-a-purpose for anyone, not only people captured on this phone).
  Future<void> pullPeople() async {
    final prog = programme;
    if (prog == null || server == null) return;
    try {
      var since = await store!.get('people_since:$prog');
      for (var page = 0; page < 20; page++) {
        final out = await server!.peopleForDevice(prog, since);
        if (out == null) return;
        for (final p in (out['people'] as List? ?? const [])) {
          await store!.saveServerPrincipal(prog, Map<String, dynamic>.from(p as Map));
        }
        since = out['until'] as String? ?? since;
        if (since != null) await store!.put('people_since:$prog', since);
        if (out['more'] != true) break;
      }
    } on ServerFailure catch (_) {
      // Try again on the next sync.
    }
  }

  String? takeMessage() {
    final m = lastMessage;
    lastMessage = null;
    return m;
  }
}
