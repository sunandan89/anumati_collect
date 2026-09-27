import 'package:flutter/material.dart';

import '../capture/draft.dart';
import '../capture/flow.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

/// M4 Choices (spec A4): every optional purpose starts off; essential
/// purposes are explained, never toggled; Yes-to-all and No-to-all carry
/// equal weight.
class PurposesScreen extends StatefulWidget {
  const PurposesScreen({super.key, required this.draft});
  final CaptureDraft draft;
  @override
  State<PurposesScreen> createState() => _PurposesScreenState();
}

class _PurposesScreenState extends State<PurposesScreen> {
  CaptureDraft get d => widget.draft;

  void _all(bool v) => setState(() {
    for (final p in d.offered.where((p) => !p.essential)) {
      d.choices[p.code] = v;
    }
  });

  @override
  Widget build(BuildContext context) {
    final l = d.lang;
    final n = d.notice!;
    final hidden = n.purposes.length != d.offered.length;
    return StepScaffold(
      bar: StepBar(title: trFor(l, 'What do you agree to?'), subtitle: stepLabel(d, 'purposes')),
      footer: FilledButton(
        onPressed: () => goNext(context, d, 'purposes'),
        child: Text(n.label('label_save') ?? trFor(l, 'Continue')),
      ),
      children: [
        for (final p in d.offered)
          p.essential
              ? PCard(
                  color: AC.sunk,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                            Muted(p.description.isNotEmpty ? p.description : trFor(l, 'Needed for the service')),
                          ],
                        ),
                      ),
                      StatusChip(trFor(l, 'Required')),
                    ],
                  ),
                )
              : PCard(
                  onTap: () => setState(() => d.choices[p.code] = !(d.choices[p.code] ?? false)),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                            Muted([if (p.description.isNotEmpty) p.description, trFor(l, 'optional')].join(' · ')),
                          ],
                        ),
                      ),
                      Semantics(
                        label: p.title,
                        child: Switch(
                          value: d.choices[p.code] ?? false,
                          onChanged: (v) => setState(() => d.choices[p.code] = v),
                        ),
                      ),
                    ],
                  ),
                ),
        if (hidden && d.flags['minor']!) Muted(trFor(l, 'Some uses are not offered to minors.')),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _all(true),
                child: Text(n.label('label_yes_all') ?? trFor(l, 'Yes to all')),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () => _all(false),
                child: Text(n.label('label_no_all') ?? trFor(l, 'No to all')),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
