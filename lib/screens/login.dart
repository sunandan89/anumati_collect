import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

/// Sign in with a Frappe user ID and password (Frappe Mobile Control
/// `mobile_auth.login`). The organisation address is remembered.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _address = TextEditingController();
  final _user = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    const FlutterSecureStorage().read(key: 'anumati.base_url').then((v) {
      if (v != null && mounted) {
        _address.text = v.replaceFirst(RegExp(r'^https?://'), '').replaceFirst(RegExp(r'/$'), '');
      }
    });
  }

  Future<void> _submit() async {
    if (_address.text.trim().isEmpty || _user.text.trim().isEmpty || _password.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await context.read<AppState>().signIn(_address.text, _user.text, _password.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
    if (err == null) _password.clear();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 24),
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: AC.leaf, borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.verified_user_outlined, color: AC.leafInk),
                ),
                const SizedBox(width: 12),
                const Text('Anumati Collect', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: LangSeg(value: Strings.uiLang, onChanged: s.setUiLang),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _address,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: tr('Organisation address'),
                hintText: tr('e.g. aaroh.frappe.cloud'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _user,
              autocorrect: false,
              decoration: InputDecoration(labelText: tr('User ID')),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: _hide,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: tr('Password'),
                suffixIcon: IconButton(
                  icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _hide = !_hide),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_error != null) ...[Note(_error!, danger: true), const SizedBox(height: 12)],
            if (s.lastMessage != null) ...[Note(s.lastMessage!), const SizedBox(height: 12)],
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(tr('Sign in')),
            ),
          ],
        ),
      ),
    );
  }
}
