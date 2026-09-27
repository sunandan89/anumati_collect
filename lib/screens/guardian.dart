import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../capture/draft.dart';
import '../capture/flow.dart';
import '../core/strings.dart';
import '../widgets/capture_tools.dart';
import '../widgets/common.dart';

/// Guardian step (spec C1, C2): who consents for a minor or a person with a
/// lawful guardian, and how the guardian was verified.
class GuardianScreen extends StatefulWidget {
  const GuardianScreen({super.key, required this.draft});
  final CaptureDraft draft;
  @override
  State<GuardianScreen> createState() => _GuardianScreenState();
}

class _GuardianScreenState extends State<GuardianScreen> {
  CaptureDraft get d => widget.draft;
  late final _name = TextEditingController(text: d.guardianName);
  late final _relation = TextEditingController(text: d.guardianRelation);
  late final _phone = TextEditingController(text: d.guardianPhone.isNotEmpty ? d.guardianPhone : d.phone);
  late final _authority = TextEditingController(text: d.guardianAuthorityRef);

  static const _types = {
    'parent': 'Parent',
    'legal': 'Legal guardian',
    'family': 'Family guardian (disability)',
    'court': 'Court / committee',
  };

  bool get _ready =>
      _name.text.trim().isNotEmpty && (d.guardianVerify == 'sms' ? d.guardianVerified : d.guardianDoc != null);

  String get _guardianDigits => _phone.text.replaceAll(RegExp(r'\D'), '');

  @override
  Widget build(BuildContext context) {
    final store = context.read<AppState>().store!;
    final types = d.flags['minor']! ? ['parent', 'legal'] : ['family', 'court', 'legal'];
    if (!types.contains(d.guardianType)) d.guardianType = types.first;
    return StepScaffold(
      bar: StepBar(title: tr('Who consents on their behalf?'), subtitle: stepLabel(d, 'guardian')),
      footer: FilledButton(
        onPressed: _ready
            ? () {
                d.guardianName = _name.text.trim();
                d.guardianRelation = _relation.text.trim();
                d.guardianPhone = _guardianDigits;
                d.guardianAuthorityRef = _authority.text.trim();
                goNext(context, d, 'guardian');
              }
            : null,
        child: Text(tr('Continue to notice')),
      ),
      children: [
        PCard(
          child: Text(
            d.flags['minor']! ? tr('For {0} · under 18', [d.fullName]) : tr('For {0} · lawful guardian', [d.fullName]),
          ),
        ),
        Muted(tr('Guardian type')),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final t in types)
              ChoiceChip(
                label: Text(tr(_types[t]!)),
                selected: d.guardianType == t,
                onSelected: (_) => setState(() => d.guardianType = t),
              ),
          ],
        ),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: tr('Guardian name')),
        ),
        TextField(
          controller: _relation,
          decoration: InputDecoration(labelText: tr('Relation')),
        ),
        if (d.guardianType == 'court' || d.guardianType == 'legal' || d.guardianType == 'family')
          TextField(
            controller: _authority,
            decoration: InputDecoration(labelText: tr('Order or authority reference')),
          ),
        Muted(tr('Verify the guardian')),
        Opt(
          value: 'sms',
          group: d.guardianVerify,
          onChanged: (v) => setState(() => d.guardianVerify = v),
          title: tr("SMS code to guardian's phone"),
          subtitle: tr('Signal, no data'),
        ),
        if (d.guardianVerify == 'sms') ...[
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: tr("Guardian's mobile")),
          ),
          if (_guardianDigits.length >= 10)
            OtpPanel(
              phone: _guardianDigits,
              lang: d.lang,
              onConfirmed: () => setState(() => d.guardianVerified = true),
            ),
        ],
        Opt(
          value: 'doc',
          group: d.guardianVerify,
          onChanged: (v) => setState(() => d.guardianVerify = v),
          title: tr('Photo of ID or order'),
          subtitle: tr('School ID, ration card, court order'),
        ),
        if (d.guardianVerify == 'doc')
          OutlinedButton.icon(
            onPressed: () async {
              final ref = await capturePhoto(store, 'guardian_document');
              if (ref != null) setState(() => d.guardianDoc = ref);
            },
            icon: Icon(d.guardianDoc == null ? Icons.photo_camera_outlined : Icons.check),
            label: Text(d.guardianDoc == null ? tr('Take photo') : tr('Photo saved')),
          ),
        Note(tr('Profiling and research are hidden for minors. Nothing is processed until the guardian is verified.')),
      ],
    );
  }
}
