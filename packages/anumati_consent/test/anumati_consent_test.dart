import 'dart:convert';

import 'package:anumati_consent/anumati_consent.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeData implements ConsentData {
  final saved = <(String, Map<String, dynamic>)>[];
  final rows = <String, List<Map<String, Object?>>>{};
  List<List>? lastFilters;

  @override
  Future<String> save(String doctype, Map<String, dynamic> data) async {
    saved.add((doctype, data));
    return data['mobile_uuid'] as String;
  }

  @override
  Future<List<Map<String, Object?>>> list(String doctype, {List<List> filters = const [], int pageSize = 200}) async {
    lastFilters = filters;
    return rows[doctype] ?? const [];
  }
}

void main() {
  final at = DateTime(2026, 10, 16, 9, 5, 7);

  test('a consent is one Consent Event record named by its mobile_uuid, with the receipt code made offline', () async {
    final data = FakeData();
    final consent = AnumatiConsent(data, clock: () => at);
    final receipt = await consent.record(
      ConsentDecision(
        principal: 'DP-00017',
        programme: 'MCH',
        granted: ['screen', 'follow'],
        denied: ['photos'],
        verificationMethod: 'evidence_only',
        evidence: [
          {'file': '/private/files/a.m4a', 'kind': 'audio', 'sha256': 'a' * 64},
        ],
      ),
    );
    final (doctype, row) = data.saved.single;
    expect(doctype, 'Anumati Consent Event');
    expect(row['mobile_uuid'], receipt.eventUuid);
    expect(receipt.code, receiptCode(receipt.eventUuid));
    expect(row['purposes_granted'], '["screen","follow"]');
    expect(jsonDecode(row['evidence'] as String), hasLength(1));
    expect(row['device_time'], '2026-10-16 09:05:07');
    expect(row.containsKey('verification_status'), isFalse, reason: 'the server decides it, never the phone');
    expect(row.containsKey('name'), isFalse);
  });

  test('withdrawal is a new event, never an edit', () async {
    final data = FakeData();
    await AnumatiConsent(data).withdraw('DP-00017', 'MCH', ['follow']);
    final row = data.saved.single.$2;
    expect(row['action'], 'withdraw');
    expect(row['purposes_denied'], '["follow"]');
    expect(row['purposes_granted'], '[]');
  });

  test('status reads the Consent State the SDK pulled', () async {
    final data = FakeData()
      ..rows['Anumati Consent State'] = [
        {'status': 'granted'},
      ];
    expect(await AnumatiConsent(data).status('DP-00017', 'MCH', 'follow'), 'granted');
    expect(data.lastFilters, [
      ['principal', '=', 'DP-00017'],
      ['purpose', '=', 'MCH-follow'],
    ]);
    expect(await AnumatiConsent(FakeData()).status('DP-00017', 'MCH', 'follow'), 'not_asked');
  });

  test('receipt code matches the server formula', () {
    expect(receiptCode('c0a8f1e2-0000-4000-8000-000000000001'), 'AN-HX34BM');
    expect(receiptCode('test-uuid-1234'), 'AN-5NBFB6');
  });
}
