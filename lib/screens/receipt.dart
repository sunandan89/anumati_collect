import 'package:flutter/material.dart';

import '../capture/draft.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

/// M7 Receipt (spec B1, B4): the consent code to write on her slip, what was
/// decided, and how to withdraw.
class ReceiptScreen extends StatelessWidget {
  const ReceiptScreen({super.key, required this.draft});
  final CaptureDraft draft;

  String _titles(List<String> codes) {
    final byCode = {for (final p in draft.offered) p.code: p.title};
    return codes.isEmpty ? tr('Nothing') : codes.map((c) => byCode[c] ?? c).join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final d = draft;
    final verifiedBy = switch (d.verifyMethod) {
      'device_sms_otp' => tr('Device SMS code'),
      'deferred' => tr('Confirm later (SMS after sync)'),
      _ => tr('Evidence only'),
    };
    return PopScope(
      canPop: false,
      child: StepScaffold(
        bar: StepBar(title: tr('Saved on this phone'), subtitle: d.programme),
        footer: FilledButton(
          onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
          child: Text(tr('Done — next beneficiary')),
        ),
        children: [
          const SizedBox(height: 8),
          const Center(
            child: CircleAvatar(
              radius: 32,
              backgroundColor: AC.leafSoft,
              child: Icon(Icons.check, color: AC.leaf, size: 32),
            ),
          ),
          Center(
            child: Text(tr('Saved on this phone'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
          ),
          Center(child: Muted(tr('Signed and chained when this phone syncs'))),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AC.raised,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AC.terra.withValues(alpha: 0.55), width: 1.5),
            ),
            child: Column(
              children: [
                Muted(tr('Consent code — write it on her slip')),
                const SizedBox(height: 6),
                SelectableText(
                  d.shortCode,
                  style: const TextStyle(
                    fontSize: 30,
                    letterSpacing: 2.4,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          PCard(
            child: Column(
              children: [
                _row(d.fullName, Strings.languages[d.lang] ?? d.lang),
                _row(tr('Granted'), _titles(d.granted)),
                _row(tr('Refused'), _titles(d.denied)),
                _row(tr('Verified by'), verifiedBy),
              ],
            ),
          ),
          PCard(child: Text(tr('Tell her: SMS STOP with this code, a missed call, or tell any worker to withdraw.'))),
        ],
      ),
    );
  }

  Widget _row(String a, String b) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(a, style: const TextStyle(color: AC.ink3, fontSize: 13)),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: Text(b, textAlign: TextAlign.right, style: const TextStyle(fontSize: 13)),
        ),
      ],
    ),
  );
}
