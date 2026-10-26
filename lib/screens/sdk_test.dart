import 'package:anumati_consent/anumati_consent.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';

/// Developer check of the new data path (solution document, spike): one consent saved through the
/// `anumati_consent` package on this app's own Frappe Mobile SDK, pushed by the SDK's standard sync,
/// then read back from the server to show it was checked, signed and chained there.
///
/// Shown only to users with the Anumati Developer or System Manager role. It writes a real consent:
/// use a test beneficiary. English only, like other developer tools.
class SdkTestScreen extends StatefulWidget {
  const SdkTestScreen({super.key});

  static bool allowedFor(AppState s) =>
      (s.sdk?.roles ?? const []).any((r) => r == 'Anumati Developer' || r == 'System Manager');

  @override
  State<SdkTestScreen> createState() => _SdkTestScreenState();
}

class _SdkTestScreenState extends State<SdkTestScreen> {
  final _ref = TextEditingController();
  final _granted = TextEditingController();
  final _log = <String>[];
  ConsentReceipt? _receipt;
  bool _busy = false;

  void _say(String line) => setState(() => _log.add(line));

  Future<void> _run(Future<void> Function() step) async {
    setState(() => _busy = true);
    try {
      await step();
    } catch (e) {
      _say('Error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() => _run(() async {
    final s = context.read<AppState>();
    final sdk = s.sdk;
    final programme = s.programme;
    if (sdk == null || programme == null) return _say('Sign in and choose a programme first.');
    final ref = _ref.text.trim();
    final codes = _granted.text.split(RegExp(r'[,\s]+')).where((c) => c.isNotEmpty).toList();
    if (ref.isEmpty || codes.isEmpty) return _say('Enter a beneficiary ID and at least one use code.');
    _say('Looking up $ref…');
    final name = await s.server!.principalName(ref);
    if (name == null) return _say('No beneficiary $ref on the server.');
    final consent = AnumatiConsent.attach(sdk);
    final receipt = await consent.record(
      ConsentDecision(
        principal: name,
        programme: programme,
        granted: codes,
        captureMode: 'self_worker_device',
        verificationMethod: 'deferred',
        // Sent on purpose: the server must ignore it and save "recorded".
      ),
    );
    setState(() => _receipt = receipt);
    _say('Saved on the phone through the SDK. Receipt ${receipt.code}, event ${receipt.eventUuid}.');
  });

  Future<void> _sync() => _run(() async {
    final s = context.read<AppState>();
    final sdk = s.sdk!;
    final r = _receipt;
    if (r == null) return _say('Save a consent first.');
    _say('Pushing the SDK outbox…');
    final result = await sdk.sync.pushSync(doctype: AnumatiConsent.doctype);
    _say('Push: ${result.status.name}${result.error == null ? '' : ' (${result.error})'}');
    for (final row in await sdk.repository.getSyncErrorsForDoc(
      doctype: AnumatiConsent.doctype,
      mobileUuid: r.eventUuid,
    )) {
      _say('Outbox: ${row.state.name} ${row.errorCode?.name ?? ''} ${row.errorMessage ?? ''}');
    }
    await _check();
  });

  Future<void> _check() async {
    final r = _receipt!;
    final sdk = context.read<AppState>().sdk!;
    _say('Reading it back from the server…');
    final doc = await sdk.api.call(
      'frappe.client.get_value',
      args: {
        'doctype': AnumatiConsent.doctype,
        'filters': {'event_uuid': r.eventUuid},
        'fieldname': ['name', 'verification_status', 'short_code', 'chain_seq', 'hash', 'captured_by', 'server_time'],
      },
    );
    final m = doc is Map ? (doc['message'] ?? doc) as Map? : null;
    if (m == null || m['name'] == null) return _say('Not on the server yet.');
    final hash = (m['hash'] as String? ?? '');
    _say(
      'On the server: ${m['name']} · chain #${m['chain_seq']} · hash ${hash.length > 12 ? hash.substring(0, 12) : hash}… '
      '· ${m['verification_status']} · by ${m['captured_by']} · at ${m['server_time']}',
    );
    _say(
      m['short_code'] == r.code
          ? 'Receipt code matches the server: ${r.code}.'
          : 'Receipt code MISMATCH: phone ${r.code}, server ${m['short_code']}.',
    );
    _say(
      m['verification_status'] == 'recorded'
          ? 'Verification set by the server ("recorded"), as expected.'
          : 'Unexpected verification status: ${m['verification_status']}.',
    );
  }

  @override
  void dispose() {
    _ref.dispose();
    _granted.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('SDK test (developer)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Saves one consent through the new consent package and this app\'s Frappe Mobile SDK, pushes it with '
            'the SDK\'s own sync, and reads it back. It writes a real consent: use a test beneficiary.\n\n'
            'Needs on the site: Mobile Configuration lists Anumati Consent Event (and Anumati Consent State, '
            'Anumati Programme, Anumati Purpose, Anumati Notice Template), and this user has the Field Worker role.',
          ),
          const SizedBox(height: 12),
          Text('Programme: ${s.programme ?? '(none chosen)'}'),
          TextField(
            controller: _ref,
            decoration: const InputDecoration(labelText: 'Beneficiary ID (principal_ref)'),
          ),
          TextField(
            controller: _granted,
            decoration: const InputDecoration(labelText: 'Use codes to grant, e.g. screen, follow'),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(onPressed: _busy ? null : _save, child: const Text('1. Save through the SDK')),
              FilledButton.tonal(
                onPressed: _busy || _receipt == null ? null : _sync,
                child: const Text('2. Sync and check'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (final line in _log)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: SelectableText(line, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
            ),
        ],
      ),
    );
  }
}
