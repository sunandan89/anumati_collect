import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../app_state.dart';
import '../capture/draft.dart';
import '../capture/flow.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../widgets/capture_tools.dart';
import '../widgets/common.dart';

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
  final _recorder = AudioRecorder();
  bool _recording = false;
  bool _listening = false;
  Map<String, dynamic>? _heard;
  bool _saving = false;
  Timer? _limit;
  int _seconds = 0;

  @override
  void dispose() {
    _limit?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording(AppState s) async {
    if (_recording) {
      await _stop(s);
      return;
    }
    if (!await _recorder.hasPermission()) {
      if (mounted) toast(context, tr('Microphone permission is needed to record.'));
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = p.join(dir.path, 'voice-${DateTime.now().microsecondsSinceEpoch}.m4a');
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 48000, sampleRate: 16000),
      path: path,
    );
    _seconds = 0;
    _limit = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() => _seconds++);
      if (_seconds >= 60) _stop(s);
    });
    setState(() => _recording = true);
  }

  Future<void> _stop(AppState s) async {
    _limit?.cancel();
    final path = await _recorder.stop();
    setState(() => _recording = false);
    if (path == null) return;
    final bytes = await File(path).readAsBytes();
    final (id, sha) = await s.store!.files!.adopt(File(path), 'm4a');
    setState(() {
      d.voice = EvidenceRef(id, 'audio', sha);
      _heard = null;
      _listening = s.voiceHelper;
    });
    if (!s.voiceHelper) return;
    // Optional hint (Sarvam): what was heard, and whether it sounds like yes or no. Never decides.
    final heard = await s.hearClip(bytes, d.lang);
    if (mounted) {
      setState(() {
        _listening = false;
        _heard = heard;
      });
    }
  }

  Widget _hint() {
    if (_listening) return Muted(tr('Checking what was said…'));
    final h = _heard;
    if (h == null) return const SizedBox.shrink();
    final (label, tone) = switch (h['meaning'] as String?) {
      'yes' => (tr('Sounds like yes'), Tone.ok),
      'no' => (tr('Sounds like no'), Tone.danger),
      _ => (tr('Not clear — listen again and decide'), Tone.warn),
    };
    return Row(
      children: [
        StatusChip(label, tone: tone),
        const SizedBox(width: 8),
        Expanded(
          child: Muted('${tr('Heard: “{0}”', [h['transcript'] ?? ''])} · ${tr('You decide; this is only a hint.')}'),
        ),
      ],
    );
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

  Widget _proofGroup(AppState s) {
    final photoKind = d.needsHelp ? 'thumbprint' : 'signature';
    return _group(tr('Record their yes · choose at least one'), d.voice != null || d.thumb != null, [
      Tile(
        icon: _recording ? Icons.stop : Icons.mic_none,
        title: tr('Voice: their “haan”'),
        subtitle: _recording ? '${tr('Recording… tap to stop')} 0:${_seconds.toString().padLeft(2, '0')}' : null,
        trailing: StatusChip(
          d.voice != null && !_recording ? tr('Saved') : tr('Tap to record'),
          tone: d.voice != null ? Tone.ok : Tone.neutral,
        ),
        onTap: () => _toggleRecording(s),
      ),
      _hint(),
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
            onPressed: missing == null && !_recording && !_saving
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
        if (d.phoneCheck)
          Note(tr('After Save, you can send a code to their phone from the server. They read it out to confirm.')),
        if (d.evidenceNeeded) _proofGroup(s),
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
