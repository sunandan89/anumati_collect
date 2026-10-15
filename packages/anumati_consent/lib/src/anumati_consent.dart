import 'dart:convert';

import 'package:frappe_mobile_sdk/frappe_mobile_sdk.dart';
import 'package:uuid/uuid.dart';

import 'consent_data.dart';
import 'receipt_code.dart';

/// One consent decision, as the consent screens collect it.
class ConsentDecision {
  ConsentDecision({
    required this.principal,
    required this.programme,
    this.action = 'grant',
    this.granted = const [],
    this.denied = const [],
    this.notice,
    this.language,
    this.captureMode,
    this.verificationMethod,
    this.guardianLink,
    this.witness,
    this.evidence = const [],
    this.noticeDelivery,
    this.noticeCompleted = false,
  });

  /// The Data Principal record's name (later: the host's own subject record).
  final String principal;
  final String programme;

  /// grant, refuse, renew or withdraw.
  final String action;
  final List<String> granted;
  final List<String> denied;
  final String? notice;
  final String? language;
  final String? captureMode;
  final String? verificationMethod;
  final String? guardianLink;
  final String? witness;

  /// Uploaded evidence: `{file, kind, sha256}` each.
  final List<Map<String, String>> evidence;
  final String? noticeDelivery;
  final bool noticeCompleted;
}

/// What the worker can write on the slip straight away, offline.
class ConsentReceipt {
  const ConsentReceipt(this.eventUuid, this.code);

  final String eventUuid;
  final String code;
}

/// Consent capture on the host app's Frappe Mobile SDK.
///
/// Every decision is one `Consent Event` record saved through the SDK's offline repository; the SDK's
/// own sync pushes it (a standard insert) and the server's Consent Event DocType checks, signs and chains
/// it. Nothing here talks to the server directly. The phone never decides the verification status: the
/// server does.
class AnumatiConsent {
  AnumatiConsent(this.data, {Uuid? uuid, DateTime Function()? clock})
    : _uuid = uuid ?? const Uuid(),
      _clock = clock ?? DateTime.now;

  /// Attaches to the host's SDK: its login, database, outbox and sync.
  factory AnumatiConsent.attach(FrappeSDK sdk) => AnumatiConsent(SdkConsentData(sdk));

  static const doctype = 'Consent Event';

  final ConsentData data;
  final Uuid _uuid;
  final DateTime Function() _clock;

  /// Saves the decision on the phone (encrypted SDK database + outbox) and returns the receipt code.
  Future<ConsentReceipt> record(ConsentDecision d, {String channel = 'app'}) async {
    final id = _uuid.v4();
    await data.save(doctype, {
      'mobile_uuid': id,
      'principal': d.principal,
      'programme': d.programme,
      'action': d.action,
      'purposes_granted': jsonEncode(d.granted),
      'purposes_denied': jsonEncode(d.denied),
      'channel': channel,
      'device_time': deviceTime(_clock()),
      'notice': ?d.notice,
      'language': ?d.language,
      'capture_mode': ?d.captureMode,
      'verification_method': ?d.verificationMethod,
      'guardian_link': ?d.guardianLink,
      'witness': ?d.witness,
      if (d.evidence.isNotEmpty) 'evidence': jsonEncode(d.evidence),
      'notice_delivery': ?d.noticeDelivery,
      if (d.noticeCompleted) 'notice_completed': 1,
    });
    return ConsentReceipt(id, receiptCode(id));
  }

  /// Withdraws [purposes] for a person (offline too); the server orders it against other decisions.
  Future<ConsentReceipt> withdraw(
    String principal,
    String programme,
    List<String> purposes, {
    String channel = 'app',
  }) => record(
    ConsentDecision(principal: principal, programme: programme, action: 'withdraw', denied: purposes),
    channel: channel,
  );

  /// The person's last known status for one purpose, from the Consent State the SDK pulled: granted,
  /// withdrawn, refused, or not_asked. A decision saved on this phone but not yet synced is not in it.
  Future<String> status(String principal, String programme, String purpose) async {
    final rows = await data.list(
      'Consent State',
      filters: [
        ['principal', '=', principal],
        ['purpose', '=', '$programme-$purpose'],
      ],
      pageSize: 1,
    );
    return rows.isEmpty ? 'not_asked' : (rows.first['status'] as String? ?? 'not_asked');
  }

  /// The site's naive datetime format, in the phone's local time (the server caps it at receipt time).
  static String deviceTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}
