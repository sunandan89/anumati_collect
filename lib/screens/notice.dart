import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../capture/draft.dart';
import '../capture/flow.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

/// M3 Notice (spec A1, A3): the live notice in her language. Choices unlock
/// only after the audio has played through or the text has been read to the
/// end. The audio is the reviewed recording when the organisation has one;
/// otherwise the phone reads the (reviewed) notice text aloud with its own
/// voice, so people who can't read still hear the whole notice.
class NoticeScreen extends StatefulWidget {
  const NoticeScreen({super.key, required this.draft});
  final CaptureDraft draft;
  @override
  State<NoticeScreen> createState() => _NoticeScreenState();
}

class _NoticeScreenState extends State<NoticeScreen> {
  CaptureDraft get d => widget.draft;
  final _scroll = ScrollController();
  AudioPlayer? _player;
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;
  bool _playing = false;
  bool _loaded = false;
  bool _byAi = false; // recording made with Sarvam AI's voice (and approved by a reviewer)
  String? _card;
  final _subs = <StreamSubscription>[];

  // Phone voice (text-to-speech) when there is no reviewed recording.
  final _tts = FlutterTts();
  bool _speaking = false;
  bool _ttsUnavailable = false;
  int _chunk = 0;
  List<String> _chunks = const [];

  @override
  void initState() {
    super.initState();
    _load();
    _scroll.addListener(_onScroll);
  }

  Future<void> _load() async {
    final s = context.read<AppState>();
    d.notice = await s.notice(d.lang);
    final audio = d.notice == null ? null : await s.audioPath(d.lang);
    _byAi = await s.audioByAi(d.lang);
    _card = await s.cardPath(d.lang);
    if (audio != null) {
      final player = AudioPlayer();
      try {
        _dur = await player.setFilePath(audio) ?? Duration.zero;
        _player = player;
        _subs.add(player.positionStream.listen((p) => setState(() => _pos = p)));
        _subs.add(
          player.playerStateStream.listen((st) {
            setState(() => _playing = st.playing);
            if (st.processingState == ProcessingState.completed) {
              setState(() {
                d.noticeDone = true;
                d.noticeDelivery = 'recording';
              });
              player.pause();
            }
          }),
        );
      } catch (_) {
        await player.dispose();
      }
    }
    setState(() => _loaded = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  void _onScroll() {
    if (_player != null || d.noticeDone || !_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 24) {
      setState(() {
        d.noticeDone = true;
        // The worker reads it to her when she needs help reading; otherwise she read it herself.
        if (d.noticeDelivery.isEmpty) {
          d.noticeDelivery = d.flags['read']! || d.needsGuardian ? 'read_aloud' : 'read_on_screen';
        }
      });
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player?.dispose();
    _speaking = false;
    _tts.stop();
    _scroll.dispose();
    super.dispose();
  }

  /// The notice as short spoken chunks (Android limits one utterance to ~4000 chars).
  List<String> _spokenChunks(Notice n) {
    final l = d.lang;
    final parts = <String>[
      if (n.summary.isNotEmpty) n.summary,
      if (d.offered.isNotEmpty)
        '${trFor(l, 'Why we need this')}. ${d.offered.map((p) => '${p.title}. ${p.description}').join(' ')}',
      if (n.fullText.isNotEmpty) '${trFor(l, 'What we collect')}. ${_plain(n.fullText)}',
      if (n.rightsText.isNotEmpty) '${trFor(l, 'Your rights')}. ${_plain(n.rightsText)}',
      if (n.withdrawalMethods.isNotEmpty) '${trFor(l, 'How to withdraw')}. ${_plain(n.withdrawalMethods)}',
      if (n.complaintRoute.isNotEmpty || n.dpoContact.isNotEmpty)
        '${trFor(l, 'Complaints')}. ${_plain(n.dpoContact)} ${_plain(n.complaintRoute)}',
    ];
    return [
      for (final p in parts)
        for (var i = 0; i < p.length; i += 3000) p.substring(i, (i + 3000).clamp(0, p.length)),
    ];
  }

  Future<void> _speak(Notice n) async {
    if (_speaking) {
      _speaking = false;
      await _tts.stop();
      setState(() {});
      return;
    }
    final locale = d.lang == 'hi' ? 'hi-IN' : 'en-IN';
    final available = await _tts.isLanguageAvailable(locale);
    if (available != true) {
      setState(() => _ttsUnavailable = true);
      return;
    }
    await _tts.setLanguage(locale);
    await _tts.setSpeechRate(0.45);
    await _tts.awaitSpeakCompletion(true);
    _chunks = _spokenChunks(n);
    if (_chunk >= _chunks.length) _chunk = 0;
    setState(() => _speaking = true);
    while (_speaking && _chunk < _chunks.length) {
      await _tts.speak(_chunks[_chunk]);
      if (!_speaking || !mounted) return;
      setState(() => _chunk++);
    }
    if (mounted && _chunk >= _chunks.length) {
      setState(() {
        _speaking = false;
        d.noticeDone = true;
        d.noticeDelivery = 'phone_voice';
      });
    }
  }

  Widget _voiceCard(Notice n) {
    final l = d.lang;
    final total = _chunks.isEmpty ? _spokenChunks(n).length : _chunks.length;
    return PCard(
      borderColor: AC.leaf,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: AC.leaf,
                  foregroundColor: AC.leafInk,
                  minimumSize: const Size(50, 50),
                ),
                onPressed: () => _speak(n),
                icon: Icon(_speaking ? Icons.stop : Icons.volume_up),
                tooltip: _speaking ? tr('Stop') : tr('Listen to the notice'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.noticeDone ? trFor(l, 'Notice played in full') : trFor(l, 'Listen to the notice'),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Muted(tr('Phone voice · the notice is read aloud by this phone')),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: d.noticeDone ? 1 : (total == 0 ? 0 : _chunk / total),
            color: AC.leaf,
            backgroundColor: AC.line2,
          ),
          if (_ttsUnavailable) ...[
            const SizedBox(height: 8),
            Note(tr('This phone has no voice for this language. Read the notice aloud yourself.')),
          ],
        ],
      ),
    );
  }

  String _mm(Duration t) => '${t.inMinutes}:${(t.inSeconds % 60).toString().padLeft(2, '0')}';

  Widget _section(String title, String body) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AC.raised,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AC.line2),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(body, style: const TextStyle(fontSize: 14)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final n = d.notice;
    final l = d.lang;
    if (!_loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (n == null) {
      return Scaffold(
        appBar: StepBar(title: tr('Play the full notice')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Note(tr('This programme has no published notice yet.')),
        ),
      );
    }
    final why = [
      for (final p in d.offered) '• ${p.title}${p.description.isNotEmpty ? ': ${p.description}' : ''}',
    ].join('\n');
    return StepScaffold(
      controller: _scroll,
      bar: StepBar(title: trFor(l, 'Notice'), subtitle: stepLabel(d, 'notice')),
      footer: FilledButton(
        onPressed: d.noticeDone
            ? () {
                _player?.pause();
                _speaking = false;
                _tts.stop();
                goNext(context, d, 'notice');
              }
            : null,
        child: Text(trFor(l, 'Continue')),
      ),
      children: [
        if (l != 'en' && n.translation == null)
          Note(tr('This language has no reviewed notice yet. Read the English notice aloud and explain it.')),
        if (_player != null)
          PCard(
            borderColor: AC.leaf,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: AC.leaf,
                        foregroundColor: AC.leafInk,
                        minimumSize: const Size(50, 50),
                      ),
                      onPressed: () => _playing ? _player!.pause() : _player!.play(),
                      icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            d.noticeDone ? trFor(l, 'Notice played in full') : trFor(l, 'Play the full notice'),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Muted('${tr('Reviewed recording')} · ${_mm(_pos)} / ${_mm(_dur)}'),
                          if (_byAi)
                            Row(
                              children: [
                                const Icon(Icons.graphic_eq, size: 14, color: AC.leaf),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    tr('Natural voice · Powered by Sarvam AI'),
                                    style: const TextStyle(fontSize: 12, color: AC.leaf, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: _dur.inMilliseconds == 0 ? 0 : (_pos.inMilliseconds / _dur.inMilliseconds).clamp(0, 1),
                  color: AC.leaf,
                  backgroundColor: AC.line2,
                ),
              ],
            ),
          ),
        if (_player == null) _voiceCard(n),
        if (_card != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(File(_card!), fit: BoxFit.contain, semanticLabel: trFor(l, 'Notice')),
          ),
        if (n.summary.isNotEmpty) Text(n.summary, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        if (why.isNotEmpty) _section(trFor(l, 'Why we need this'), why),
        if (n.fullText.isNotEmpty) _section(trFor(l, 'What we collect'), _plain(n.fullText)),
        if (n.rightsText.isNotEmpty) _section(trFor(l, 'Your rights'), _plain(n.rightsText)),
        if (n.withdrawalMethods.isNotEmpty) _section(trFor(l, 'How to withdraw'), _plain(n.withdrawalMethods)),
        if (n.complaintRoute.isNotEmpty || n.dpoContact.isNotEmpty)
          _section(
            trFor(l, 'Complaints'),
            [n.dpoContact, n.complaintRoute].where((s) => s.isNotEmpty).map(_plain).join('\n'),
          ),
        if (n.crossBorder.isNotEmpty) Note(trFor(l, 'Data may be sent outside India: {0}', [_plain(n.crossBorder)])),
        if (!d.noticeDone)
          Note(
            _player != null
                ? trFor(l, 'Choices unlock when the notice has played through')
                : trFor(l, 'Choices unlock when you have read to the end'),
          ),
      ],
    );
  }

  /// Notice fields may carry simple HTML from the Desk editor.
  static String _plain(String html) => html
      .replaceAll(RegExp(r'<br\s*/?>|</p>|</li>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .trim();
}
