import 'package:flutter/material.dart';

import '../capture/draft.dart';
import '../capture/flow.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

/// About the person: the extra questions this programme asks, after the notice and choices, and only
/// when the programme switched them on (none by default). Each is listed in the notice; reports show
/// totals only. For a parent or guardian this is the last screen: tick and Save.
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key, required this.draft});
  final CaptureDraft draft;
  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  CaptureDraft get d => widget.draft;
  final _text = <String, TextEditingController>{};
  bool _saving = false;

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _question(ProfileQuestion q) {
    final l = d.lang;
    final label = q.required ? q.question : '${q.question} ${trFor(l, '(optional)')}';
    if (q.answerType == 'choice') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (value, shown) in q.options)
                ChoiceChip(
                  label: Text(shown),
                  selected: d.profile[q.code] == value,
                  onSelected: (on) => setState(() => on ? d.profile[q.code] = value : d.profile.remove(q.code)),
                ),
            ],
          ),
        ],
      );
    }
    final number = q.answerType == 'number' || q.answerType == 'year';
    final c = _text.putIfAbsent(q.code, () => TextEditingController(text: d.profile[q.code] ?? ''));
    return TextField(
      controller: c,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      maxLength: number ? 4 : 140,
      onChanged: (v) => setState(() {
        final t = number ? v.replaceAll(RegExp(r'\D'), '') : v.trim();
        t.isEmpty ? d.profile.remove(q.code) : d.profile[q.code] = t;
      }),
      decoration: InputDecoration(labelText: label, counterText: ''),
    );
  }

  Future<void> _next() async {
    if (isLastStep(d, 'about')) {
      setState(() => _saving = true);
      await finishCapture(context, d);
    } else {
      goNext(context, d, 'about');
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = isLastStep(d, 'about');
    final missing = missingText(last ? d.missing : [if (d.missing.contains('answers')) 'answers']);
    return StepScaffold(
      bar: StepBar(title: trFor(d.lang, 'About the person'), subtitle: stepLabel(d, 'about')),
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
            onPressed: missing == null && !_saving ? _next : null,
            child: Text(last ? tr('Save') : tr('Continue')),
          ),
        ],
      ),
      children: [
        for (final q in d.questions) _question(q),
        if (d.questions.any((q) => q.sensitive))
          Muted(tr('Some of these are sensitive. The person may choose “Prefer not to say”.')),
        Note(
          tr(
            'These are listed in the notice under “What we collect”. Reports show only totals, never one person\'s answers.',
          ),
        ),
        if (last)
          CheckCard(value: d.attested, label: attestationText(d), onChanged: (v) => setState(() => d.attested = v)),
      ],
    );
  }
}
