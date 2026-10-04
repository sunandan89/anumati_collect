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

/// Step 2 for a parent or guardian (spec C1, C2; design A2-A4). The guardian is verified after Save by a
/// code the server texts to their phone; a photo of their ID is optional, and needed only when they have
/// no phone.
/// A guardian other than a parent, and every guardian of an adult who can't decide alone, gives the
/// number of the order that appointed them. With no order yet, consent can't be taken: nothing is saved
/// and the coordinator is told, without the person's details.
class GuardianScreen extends StatefulWidget {
  const GuardianScreen({super.key, required this.draft});
  final CaptureDraft draft;
  @override
  State<GuardianScreen> createState() => _GuardianScreenState();
}

class _GuardianScreenState extends State<GuardianScreen> {
  CaptureDraft get d => widget.draft;
  late final _name = TextEditingController(text: d.guardianName);
  late final _phone = TextEditingController(text: d.guardianPhone);
  late final _order = TextEditingController(text: d.guardianAuthorityRef);
  bool _telling = false;

  @override
  void initState() {
    super.initState();
    // Server code (MSG91) when online, unless the programme always uses the worker's phone.
    context.read<AppState>().online().then((v) {
      if (mounted) setState(() => d.online = v);
    });
  }

  bool get _child => d.flags['minor']!;

  static const _childTypes = {'mother': 'Mother', 'father': 'Father', 'other': 'Other guardian'};
  static const _appointedBy = {
    'committee': 'Local Level Committee',
    'court': 'Court',
    'other': 'Other authority',
    'none': 'No order yet',
  };
  static const _relations = ['Parent', 'Brother / sister', 'Spouse', 'Other'];

  void _sync() {
    d.guardianName = _name.text.trim();
    d.guardianAuthorityRef = _order.text.trim();
    final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
    if (digits != d.guardianPhone) {
      d.guardianPhone = digits;
      d.otpConfirmed = false; // a new number needs a new code
    }
  }

  Widget _chips(Map<String, String> options, String selected, ValueChanged<String> onSelected) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final e in options.entries)
        ChoiceChip(label: Text(tr(e.value)), selected: selected == e.key, onSelected: (_) => onSelected(e.key)),
    ],
  );

  Widget _photo(String label, EvidenceRef? ref, String kind, ValueChanged<EvidenceRef> saved) {
    final store = context.read<AppState>().store!;
    return Tile(
      icon: ref == null ? Icons.photo_camera_outlined : Icons.check,
      title: label,
      trailing: StatusChip(
        ref == null ? tr('Tap to capture') : tr('Saved'),
        tone: ref == null ? Tone.neutral : Tone.ok,
      ),
      onTap: () async {
        final r = await capturePhoto(store, kind);
        if (r != null) setState(() => saved(r));
      },
    );
  }

  Future<void> _informCoordinator() async {
    setState(() => _telling = true);
    await context.read<AppState>().informCoordinator();
    if (!mounted) return;
    toast(context, tr('Your coordinator will be told. Nothing about the person was saved.'));
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Widget _stop() => PCard(
    borderColor: AC.terra,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr("Consent can't be taken yet"),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AC.danger),
        ),
        const SizedBox(height: 6),
        Text(
          tr(
            "For an adult who can't decide alone, only a guardian appointed by a court or the Local Level Committee can give consent.",
          ),
        ),
        const SizedBox(height: 6),
        Text(
          tr(
            "The family can apply to the Local Level Committee (National Trust) or a court. The person can still be helped today; their data just isn't recorded under consent.",
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    _sync();
    final parent = _child && d.guardianType != 'other';
    if (d.guardianStop) {
      return StepScaffold(
        bar: StepBar(title: tr("Guardian's details"), subtitle: stepLabel(d, 'guardian')),
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(onPressed: _telling ? null : _informCoordinator, child: Text(tr('Inform coordinator'))),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: () => Navigator.pop(context), child: Text(tr('Back'))),
          ],
        ),
        children: [
          Muted(tr('Guardian appointed by')),
          _chips(_appointedBy, d.guardianType, (v) => setState(() => d.guardianType = v)),
          _stop(),
          Muted(tr("Nothing is saved. Your coordinator gets a note to follow up, without the person's details.")),
        ],
      );
    }
    final missing = missingText(d.guardianMissing);
    return StepScaffold(
      bar: StepBar(
        title: _child ? tr("Parent's details") : tr("Guardian's details"),
        subtitle: stepLabel(d, 'guardian'),
      ),
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
            onPressed: missing == null ? () => goNext(context, d, 'guardian') : null,
            child: Text(tr('Continue')),
          ),
        ],
      ),
      children: [
        PCard(
          child: Text(
            _child
                ? tr('For {0} · under 18', [d.fullName])
                : tr("For {0} · adult who can't decide alone", [d.fullName]),
          ),
        ),
        if (_child) ...[
          Muted(tr('Who is consenting?')),
          _chips(_childTypes, d.guardianType, (v) => setState(() => d.guardianType = v)),
        ] else ...[
          Muted(tr('Guardian appointed by')),
          _chips(_appointedBy, d.guardianType, (v) => setState(() => d.guardianType = v)),
        ],
        if (d.guardianNeedsOrder) ...[
          TextField(
            controller: _order,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: tr('Order number')),
          ),
          _photo(tr('Photo of the order (optional)'), d.guardianOrder, 'guardian_order', (r) => d.guardianOrder = r),
        ],
        if (!_child) ...[
          Muted(tr('Relation')),
          _chips({for (final r in _relations) r: r}, d.guardianRelation, (v) => setState(() => d.guardianRelation = v)),
        ],
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: parent ? tr("Parent's name") : tr("Guardian's name")),
        ),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: parent ? tr("Parent's mobile") : tr("Guardian's mobile")),
        ),
        if (d.guardianPhone.length >= 10 && !d.workerCode)
          Muted(tr('After Save, a code is sent to this number from the server. They read it out to confirm.')),
        if (d.guardianPhone.length >= 10 && d.workerCode) ...[
          Muted(
            d.online
                ? tr("This programme sends codes from your phone. The guardian's voice “haan” is needed with the code.")
                : tr("No internet: the code goes from your phone. The guardian's voice “haan” is needed with it."),
          ),
          if (d.verifyMethod == 'deferred')
            Muted(tr('Confirm later: an SMS goes to {0} after sync.', [d.guardianPhone]))
          else ...[
            OtpPanel(
              key: ValueKey(d.guardianPhone),
              phone: d.guardianPhone,
              lang: d.lang,
              onConfirmed: () => setState(() {
                d.verifyMethod = 'device_sms_otp';
                d.otpConfirmed = true;
              }),
            ),
            if (d.allowedMethods.contains('deferred') && !d.otpConfirmed)
              TextButton(
                onPressed: () => setState(() => d.verifyMethod = 'deferred'),
                child: Text(tr("Can't get the code now? Confirm later by SMS")),
              ),
          ],
          VoiceHaanTile(
            title: tr('Voice: the guardian’s “haan”'),
            value: d.voice,
            lang: d.lang,
            onSaved: (r) => setState(() => d.voice = r),
          ),
        ],
        _photo(
          switch ((parent, d.guardianPhone.isEmpty)) {
            (true, true) => tr("Photo of the parent's ID"),
            (true, false) => tr("Photo of the parent's ID (optional)"),
            (false, true) => tr("Photo of the guardian's ID"),
            (false, false) => tr("Photo of the guardian's ID (optional)"),
          },
          d.guardianDoc,
          'guardian_document',
          (r) => d.guardianDoc = r,
        ),
        if (d.guardianPhone.isEmpty)
          Muted(tr('No phone? Then the ID photo is required, because it becomes the proof.')),
      ],
    );
  }
}
