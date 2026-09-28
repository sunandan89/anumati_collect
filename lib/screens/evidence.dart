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
import '../widgets/capture_tools.dart';
import '../widgets/common.dart';

/// M5 Evidence (spec A7, section 5 capture modes): her own choice on the
/// phone, or assisted evidence (voice clip up to 60 s, thumbprint photo)
/// with a witness, plus the worker's attestation in every case.
class EvidenceScreen extends StatefulWidget {
  const EvidenceScreen({super.key, required this.draft});
  final CaptureDraft draft;
  @override
  State<EvidenceScreen> createState() => _EvidenceScreenState();
}

class _EvidenceScreenState extends State<EvidenceScreen> {
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

  bool get _assisted => d.flags['read']! || d.needsGuardian;

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
    if (_listening) return Muted(tr('Checking what she said…'));
    final h = _heard;
    if (h == null) return const SizedBox.shrink();
    final meaning = h['meaning'] as String?;
    final (label, tone) = switch (meaning) {
      'yes' => (tr('Sounds like yes'), Tone.ok),
      'no' => (tr('Sounds like no'), Tone.danger),
      _ => (tr('Not clear — listen again and decide'), Tone.warn),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          StatusChip(label, tone: tone),
          const SizedBox(width: 8),
          Expanded(
            child: Muted('${tr('Heard: “{0}”', [h['transcript'] ?? ''])} · ${tr('You decide; this is only a hint.')}'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    d.witness = _witness.text;
    d.witnessRelation = _relation.text;
    return StepScaffold(
      bar: StepBar(title: tr('Record her consent'), subtitle: stepLabel(d, 'evidence')),
      footer: FilledButton(
        onPressed: d.evidenceReady && !_recording && !_saving
            ? () async {
                if (isLastStep(d, 'evidence')) {
                  setState(() => _saving = true);
                  await finishCapture(context, d);
                } else {
                  goNext(context, d, 'evidence');
                }
              }
            : null,
        child: Text(isLastStep(d, 'evidence') ? tr('Save') : tr('Continue to verification')),
      ),
      children: [
        if (!_assisted)
          CheckCard(
            value: d.selfChosen,
            label: '${tr('She chose on this phone herself')}\n${tr('No help was needed to read or choose')}',
            onChanged: (v) => setState(() => d.selfChosen = v),
          ),
        if (!d.selfChosen) ...[
          Muted(
            d.needsGuardian
                ? tr('Record the guardian saying yes (optional when the guardian is verified)')
                : tr('At least one, plus a witness for assisted consent'),
          ),
          Tile(
            icon: _recording ? Icons.stop : Icons.mic_none,
            title: tr('Voice — record her “haan”'),
            subtitle: _recording ? '${tr('Recording… tap to stop')} 0:${_seconds.toString().padLeft(2, '0')}' : null,
            trailing: StatusChip(
              d.voice != null && !_recording ? tr('{0} saved', ['✓']) : tr('Tap to record'),
              tone: d.voice != null ? Tone.ok : Tone.neutral,
            ),
            onTap: () => _toggleRecording(s),
          ),
          _hint(),
          Tile(
            icon: Icons.fingerprint,
            title: tr('Thumbprint on slip'),
            subtitle: tr('Photo of the impression'),
            trailing: StatusChip(
              d.thumb != null ? tr('Photo saved') : tr('Tap to capture'),
              tone: d.thumb != null ? Tone.ok : Tone.neutral,
            ),
            onTap: () async {
              final ref = await capturePhoto(s.store!, 'thumbprint');
              if (ref != null) setState(() => d.thumb = ref);
            },
          ),
          TextField(
            controller: _witness,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: d.needsGuardian ? tr('Witness name (optional)') : tr('Witness name'),
            ),
          ),
          TextField(
            controller: _relation,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: tr('Relation / role')),
          ),
        ],
        CheckCard(
          value: d.attested,
          label: tr(
            'I played the full notice in her language, answered her questions, and she chose freely. Nothing was pre-selected.',
          ),
          onChanged: (v) => setState(() => d.attested = v),
        ),
      ],
    );
  }
}
