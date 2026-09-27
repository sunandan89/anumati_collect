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
    final (id, sha) = await s.store!.files!.adopt(File(path), 'm4a');
    setState(() => d.voice = EvidenceRef(id, 'audio', sha));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    d.witness = _witness.text;
    d.witnessRelation = _relation.text;
    return StepScaffold(
      bar: StepBar(title: tr('Record her consent'), subtitle: stepLabel(d, 'evidence')),
      footer: FilledButton(
        onPressed: d.evidenceReady && !_recording ? () => goNext(context, d, 'evidence') : null,
        child: Text(tr('Continue to verification')),
      ),
      children: [
        if (!_assisted)
          CheckCard(
            value: d.selfChosen,
            label: '${tr('She chose on this phone herself')}\n${tr('No help was needed to read or choose')}',
            onChanged: (v) => setState(() => d.selfChosen = v),
          ),
        if (!d.selfChosen) ...[
          Muted(tr('At least one, plus a witness for assisted consent')),
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
            decoration: InputDecoration(labelText: tr('Witness name')),
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
