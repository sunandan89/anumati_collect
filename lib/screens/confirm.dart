import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../capture/draft.dart';
import '../capture/flow.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../widgets/capture_tools.dart';
import '../widgets/common.dart';
import '../widgets/voice_haan.dart';

/// Confirm and save, when the person consents for themself (spec section 5; design A1). One screen with
/// only what this person's consent needs:
/// - a phone: after Save, a code the server texts to it, which they read back (or confirm later by SMS);
/// - no phone, or the notice was read to them: their recorded "haan" or a photo of their signature or
///   thumbprint (at least one);
/// - the notice was read to them: a witness's name (relation optional);
/// - always: the worker's declaration.
class ConfirmScreen extends StatefulWidget {
  const ConfirmScreen({super.key, required this.draft});
  final CaptureDraft draft;
  @override
  State<ConfirmScreen> createState() => _ConfirmScreenState();
}

class _ConfirmScreenState extends State<ConfirmScreen> {
  CaptureDraft get d => widget.draft;
  late final _witness = TextEditingController(text: d.witness);
  late final _relation = TextEditingController(text: d.witnessRelation);
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Which route the code takes depends on internet now (the programme may also always use the worker's phone).
    context.read<AppState>().online().then((v) {
      if (mounted) setState(() => d.online = v);
    });
  }

  /// A dashed group that says how many of its items are needed, with a ✓ once done.
  Widget _group(String title, bool done, List<Widget> children) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: done ? AC.leaf : AC.terra, width: 1.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            StatusChip(done ? tr('✓ Done') : tr('0 of 1'), tone: done ? Tone.ok : Tone.danger),
          ],
        ),
        for (final c in children) ...[const SizedBox(height: 8), c],
      ],
    ),
  );

  Widget _voice() => VoiceHaanTile(
    title: tr('Voice: their “haan”'),
    value: d.voice,
    lang: d.lang,
    onSaved: (r) => setState(() => d.voice = r),
  );

  /// Code from the worker's own phone: the worker sees it, so the voice "haan" is required with it.
  Widget _workerCodeGroup() {
    final later = d.allowedMethods.contains('deferred');
    final codeDone = d.otpConfirmed || d.verifyMethod == 'deferred';
    return _group(tr('Check their phone · both needed'), codeDone && d.voice != null, [
      Muted(
        !d.online
            ? tr('No internet: the code goes from your phone. Their voice “haan” is needed with it.')
            : d.codesFromWorkerPhone
            ? tr('This programme sends codes from your phone. Their voice “haan” is needed with the code.')
            : tr(
                'SMS codes from the server are not set up yet: the code goes from your phone. Their voice “haan” is needed with it.',
              ),
      ),
      if (d.verifyMethod == 'deferred')
        Muted(tr('Confirm later: an SMS goes to {0} after sync.', [d.phone]))
      else ...[
        OtpPanel(
          phone: d.phone,
          lang: d.lang,
          onConfirmed: () => setState(() {
            d.verifyMethod = 'device_sms_otp';
            d.otpConfirmed = true;
          }),
        ),
        if (later && !d.otpConfirmed)
          TextButton(
            onPressed: () => setState(() => d.verifyMethod = 'deferred'),
            child: Text(tr("Can't get the code now? Confirm later by SMS")),
          ),
      ],
      _voice(),
    ]);
  }

  Widget _proofGroup(AppState s) {
    final photoKind = d.needsHelp ? 'thumbprint' : 'signature';
    return _group(tr('Record their yes · choose at least one'), d.voice != null || d.thumb != null, [
      _voice(),
      Tile(
        icon: Icons.fingerprint,
        title: d.needsHelp ? tr('Thumbprint on their slip') : tr('Photo of their signature or thumbprint on the slip'),
        trailing: StatusChip(
          d.thumb != null ? tr('Saved') : tr('Tap to capture'),
          tone: d.thumb != null ? Tone.ok : Tone.neutral,
        ),
        onTap: () async {
          final ref = await capturePhoto(s.store!, photoKind);
          if (ref != null) setState(() => d.thumb = ref);
        },
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    d.witness = _witness.text;
    d.witnessRelation = _relation.text;
    final byCode = {for (final p in d.offered) p.code: p.title};
    final missing = missingText(d.missing);
    final facts = [
      Strings.languages[d.lang] ?? d.lang,
      if (d.needsHelp) tr('needs help reading'),
      if (d.noPhone) tr('no phone'),
    ];
    return StepScaffold(
      bar: StepBar(title: tr('Confirm and save'), subtitle: stepLabel(d, 'confirm')),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (missing != null) ...[
            Text(
              missing,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AC.danger),
            ),
            const SizedBox(height: 6),
          ],
          FilledButton(
            onPressed: missing == null && !_saving
                ? () async {
                    setState(() => _saving = true);
                    await finishCapture(context, d);
                  }
                : null,
            child: Text(tr('Save')),
          ),
        ],
      ),
      children: [
        PCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${d.fullName} · ${facts.join(' · ')}', style: const TextStyle(fontWeight: FontWeight.w600)),
              if (d.granted.isNotEmpty) Muted(tr('Agreed: {0}', [d.granted.map((c) => byCode[c] ?? c).join(', ')])),
              if (d.denied.isNotEmpty) Muted(tr('Refused: {0}', [d.denied.map((c) => byCode[c] ?? c).join(', ')])),
            ],
          ),
        ),
        if (d.phoneCheck && !d.workerCode)
          Note(tr('After Save, you can send a code to their phone from the server. They read it out to confirm.')),
        if (d.phoneCheck && d.workerCode) _workerCodeGroup(),
        // With a worker-phone code the voice is asked for above, which also covers proof.
        if (d.evidenceNeeded && !(d.phoneCheck && d.workerCode)) _proofGroup(s),
        if (d.witnessNeeded) ...[
          Text(
            tr('Witness (needed because the notice was read to them)'),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          TextField(
            controller: _witness,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: tr('Witness name')),
          ),
          TextField(
            controller: _relation,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: tr('Relation (optional)')),
          ),
        ] else if (!d.needsHelp)
          Muted(tr('No witness: they read the notice themselves.')),
        CheckCard(value: d.attested, label: attestationText(d), onChanged: (v) => setState(() => d.attested = v)),
      ],
    );
  }
}
