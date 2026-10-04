import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../app_state.dart';
import '../capture/draft.dart';
import '../core/strings.dart';
import 'common.dart';

/// Records a short voice "haan" (up to 60 s) straight into encrypted storage. With the voice helper on,
/// shows what Sarvam heard as a hint; the worker still decides.
class VoiceHaanTile extends StatefulWidget {
  const VoiceHaanTile({super.key, required this.title, required this.value, required this.lang, required this.onSaved});
  final String title;
  final EvidenceRef? value;
  final String lang;
  final ValueChanged<EvidenceRef> onSaved;

  @override
  State<VoiceHaanTile> createState() => _VoiceHaanTileState();
}

class _VoiceHaanTileState extends State<VoiceHaanTile> {
  final _recorder = AudioRecorder();
  bool _recording = false;
  bool _listening = false;
  Map<String, dynamic>? _heard;
  Timer? _limit;
  int _seconds = 0;

  @override
  void dispose() {
    _limit?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _toggle(AppState s) async {
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
    widget.onSaved(EvidenceRef(id, 'audio', sha));
    setState(() {
      _heard = null;
      _listening = s.voiceHelper;
    });
    if (!s.voiceHelper) return;
    // Optional hint (Sarvam): what was heard, and whether it sounds like yes or no. Never decides.
    final heard = await s.hearClip(bytes, widget.lang);
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

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final saved = widget.value != null && !_recording;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Tile(
          icon: _recording ? Icons.stop : Icons.mic_none,
          title: widget.title,
          subtitle: _recording ? '${tr('Recording… tap to stop')} 0:${_seconds.toString().padLeft(2, '0')}' : null,
          trailing: StatusChip(saved ? tr('Saved') : tr('Tap to record'), tone: saved ? Tone.ok : Tone.neutral),
          onTap: () => _toggle(s),
        ),
        _hint(),
      ],
    );
  }
}
