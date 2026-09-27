import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

/// App lock. [setup] asks for a new 4-digit PIN twice (after the first sign-in); otherwise it unlocks.
/// Forgetting the PIN means signing out, which deletes everything on the phone.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, this.setup = false});
  final bool setup;
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String _pin = '';
  String? _first;
  String? _error;
  bool _busy = false;

  Future<void> _digit(String d) async {
    if (_busy || _pin.length >= 4) return;
    setState(() {
      _pin += d;
      _error = null;
    });
    if (_pin.length < 4) return;
    final s = context.read<AppState>();
    if (widget.setup) {
      if (_first == null) {
        setState(() {
          _first = _pin;
          _pin = '';
        });
      } else if (_first == _pin) {
        await s.setPin(_pin);
      } else {
        setState(() {
          _first = null;
          _pin = '';
          _error = tr('The PINs did not match. Start again.');
        });
      }
      return;
    }
    setState(() => _busy = true);
    final ok = await s.unlock(_pin);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) {
        _pin = '';
        _error = tr('Wrong PIN. {0} tries left.', [AppState.maxPinTries - s.pinTries]);
      }
    });
  }

  Future<void> _forgot() async {
    final s = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Sign out')),
        content: Text(
          [
            tr('Sign out and remove all data from this phone?'),
            if (s.pending + s.failed > 0)
              tr('{0} records are not synced yet and will be lost.', [s.pending + s.failed]),
          ].join('\n\n'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Sign out'))),
        ],
      ),
    );
    if (ok == true) await s.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.setup
        ? (_first == null ? tr('Choose a 4-digit PIN for this app') : tr('Enter the PIN again'))
        : tr('Enter your PIN');
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 32),
              const Icon(Icons.lock_outline, size: 40, color: AC.leaf),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              if (widget.setup) ...[
                const SizedBox(height: 6),
                Muted(tr('The app locks when you leave it for 5 minutes. Names and evidence stay protected.')),
              ],
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < 4; i++)
                    Container(
                      margin: const EdgeInsets.all(8),
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < _pin.length ? AC.terra : Colors.transparent,
                        border: Border.all(color: AC.terra, width: 2),
                      ),
                    ),
                ],
              ),
              if (_error != null) ...[const SizedBox(height: 8), Note(_error!, danger: true)],
              const Spacer(),
              for (final row in const [
                ['1', '2', '3'],
                ['4', '5', '6'],
                ['7', '8', '9'],
                ['', '0', '<'],
              ])
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final k in row)
                      SizedBox(
                        width: 80,
                        height: 64,
                        child: k.isEmpty
                            ? null
                            : TextButton(
                                onPressed: () => k == '<'
                                    ? setState(() => _pin = _pin.isEmpty ? '' : _pin.substring(0, _pin.length - 1))
                                    : _digit(k),
                                child: k == '<'
                                    ? const Icon(Icons.backspace_outlined)
                                    : Text(k, style: const TextStyle(fontSize: 26, color: AC.ink)),
                              ),
                      ),
                  ],
                ),
              const SizedBox(height: 12),
              if (!widget.setup) TextButton(onPressed: _forgot, child: Text(tr('Forgot PIN? Sign out'))),
            ],
          ),
        ),
      ),
    );
  }
}
